package main

import (
	"encoding/base64"
	"errors"
	"fmt"
	"html/template"
	"os"
	"path"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

// TocEntry models an entry in the Table of Contents.
type TocEntry struct {
	Id    string
	Title string
}

type TocSection struct {
	TocEntry
	Subsections []TocEntry
}

type Article struct {
	Title      string
	Subtitle   string
	CreatedAt  time.Time
	ModifiedAt time.Time
	Keywords   []string
	Document   Env
	URL        string
}

type PostListRenderContext struct {
	Title    string
	Articles []Article
}

type PageRenderContext struct {
	Title string
	Body  template.HTML
	URL   string
}

type PostRenderContext struct {
	Title      string
	Subtitle   string
	CreatedAt  time.Time
	ModifiedAt time.Time
	Keywords   []string
	URL        string
	Toc        []TocSection
	Body       template.HTML
	PrevPost   *Article
	NextPost   *Article
}

func (a *Article) Toc() (sections []TocSection, err error) {
	var s TocSection
	var e TocEntry
	var title string
	sawSection := false
	for _, n := range a.Document.body {
		switch v := n.(type) {
		case Cmd:
			switch v.name {
			case SymSection:
				if sawSection {
					sections = append(sections, s)
				}
				sawSection = true
				s.Subsections = nil
				if err = extractTextArgument(v, 0, &s.Id); err != nil {
					return
				}
				if err = extractTextArgument(v, 1, &title); err != nil {
					return
				}
				s.Title = renderTitle(title)
			case SymSubSection:
				if err = extractTextArgument(v, 0, &e.Id); err != nil {
					return
				}
				if err = extractTextArgument(v, 1, &title); err != nil {
					return
				}
				if !sawSection {
					err = fmt.Errorf("subsection `%s' appears before any section", e.Title)
					return
				}
				e.Title = renderTitle(title)
				s.Subsections = append(s.Subsections, e)
			}
		default:
			continue
		}
	}
	if sawSection {
		sections = append(sections, s)
	}
	return
}

func extractTextArgument(c Cmd, i int, dst *string) error {
	if len(c.args) <= i {
		return fmt.Errorf("expected the %s command to have at least %d arguments", SymbolName(c.name), i+1)
	}
	arg := c.args[i]
	if len(arg) != 1 {
		return fmt.Errorf("expected the %s command argument #%d to be one text node, got %s", SymbolName(c.name), i+1, arg)
	}
	switch v := arg[0].(type) {
	case Text:
		*dst = v.body
		return nil
	default:
		return fmt.Errorf("expected the %s command #%d argument to be one text node, got %s", SymbolName(c.name), i+1, arg)
	}
}

func extractIntArgument(c Cmd, i int, dst *int) error {
	var value string
	if err := extractTextArgument(c, i, &value); err != nil {
		return err
	}
	n, err := strconv.Atoi(value)
	if err != nil {
		return fmt.Errorf("failed to parse integer from string %s: %w", value, err)
	}
	*dst = n
	return nil
}

func extractDateArgument(c Cmd, i int, dst *time.Time) error {
	var value string
	if err := extractTextArgument(c, i, &value); err != nil {
		return err
	}
	t, err := time.Parse("2006-01-02", value)
	if err != nil {
		return fmt.Errorf("failed to parse date %s: %w", value, err)
	}
	*dst = t
	return nil
}

// ArticleMetadata extracts the article metadata from the article AST.
func ArticleMetadata(ast []Node) (article Article, err error) {
	// All the artice metadata is at the top level.
	// We don't have to look deep into the tree.
	for _, n := range ast {
		switch v := n.(type) {
		case Cmd:
			switch v.name {
			case SymTitle:
				if err = extractTextArgument(v, 0, &article.Title); err != nil {
					return
				}
				article.Title = renderTitle(article.Title)
			case SymSubtitle:
				if err = extractTextArgument(v, 0, &article.Subtitle); err != nil {
					return
				}
				article.Subtitle = renderTitle(article.Subtitle)
			case SymDate:
				if err = extractDateArgument(v, 0, &article.CreatedAt); err != nil {
					return
				}
			case SymModified:
				if err = extractDateArgument(v, 0, &article.ModifiedAt); err != nil {
					return
				}
			case SymKeyword:
				var kw string
				if err = extractTextArgument(v, 0, &kw); err != nil {
					return
				}
				article.Keywords = append(article.Keywords, kw)
			}
		case Env:
			switch v.name {
			case SymDocument:
				article.Document = v
			default:
				continue
			}
		default:
			continue
		}
	}
	return
}

func (article *Article) RenderBody() (html template.HTML, err error) {
	var buf strings.Builder
	var rc RenderingCtx
	rc.parent = RootCtx
	if err = renderGenericSeq(&rc, &buf, article.Document.body); err != nil {
		return
	}
	html = template.HTML(buf.String())
	return
}

type ParentContext int

const (
	GenericCtx ParentContext = iota
	RootCtx
	CodeCtx
	OrderedListCtx
	UnorderedListCtx
)

type RenderingCtx struct {
	parent ParentContext
	// How many items we have rendered in the list context.
	listCounter    int
	sectionCounter int
}

func renderGenericSeq(rc *RenderingCtx, buf *strings.Builder, seq []Node) error {
	for _, n := range seq {
		switch v := n.(type) {
		case Text:
			renderText(rc, buf, v.body)
		case Cmd:
			if err := renderGenericCmd(rc, buf, v); err != nil {
				return err
			}
		case Env:
			if err := renderGenericEnv(rc, buf, v); err != nil {
				return err
			}
		}
	}
	if rc.parent == RootCtx && rc.sectionCounter > 0 {
		// Explicitly close the last section
		buf.WriteString("</section>")
	}
	return nil
}

func renderTitle(title string) string {
	var buf strings.Builder
	var rc RenderingCtx
	renderText(&rc, &buf, title)
	return buf.String()
}

func renderCodeText(rc *RenderingCtx, buf *strings.Builder, text string) {
	i, n := 0, len(text)
	for i < n {
		c, size := utf8.DecodeRuneInString(text[i:])
		switch c {
		case '&':
			buf.WriteString("&amp;")
		case '<':
			buf.WriteString("&lt;")
		case '>':
			buf.WriteString("&gt;")
		default:
			buf.WriteRune(c)
		}
		i += size
	}
}

func renderText(rc *RenderingCtx, buf *strings.Builder, text string) {
	if rc.parent == CodeCtx {
		renderCodeText(rc, buf, text)
		return
	}
	i, n := 0, len(text)
	for i < n {
		c, size := utf8.DecodeRuneInString(text[i:])
		if c == '&' {
			buf.WriteString("&amp;")
		}
		if rc.parent == CodeCtx {
			buf.WriteRune(c)
			i += size
			continue
		}

		switch c {
		case '-':
			if strings.HasPrefix(text[i:], "---") {
				buf.WriteRune('—')
				i += 3
				continue
			}
			if strings.HasPrefix(text[i:], "--") {
				buf.WriteRune('–')
				i += 2
				continue
			}
			buf.WriteRune(c)
		case '\'':
			if strings.HasPrefix(text[i:], "''") {
				buf.WriteRune('”')
				i += 2
				continue
			}
			buf.WriteRune('’')
		case '`':
			if strings.HasPrefix(text[i:], "``") {
				buf.WriteRune('“')
				i += 2
				continue
			}
			buf.WriteRune(c)
		case '\n':
			if strings.HasPrefix(text[i:], "\n\n") {
				buf.WriteString("<p>")
				i += 2
				continue
			}
			buf.WriteRune(c)
		case '&':
			buf.WriteString("&amp;")
		case '<':
			buf.WriteString("&lt;")
		case '>':
			buf.WriteString("&gt;")
		default:
			buf.WriteRune(c)
		}
		i += size
	}
}

func optsToCssClasses(opts []sym) string {
	if len(opts) == 0 {
		return ""
	}
	names := make([]string, len(opts))
	for i, opt := range opts {
		names[i] = SymbolName(opt)
	}
	return strings.Join(names, " ")
}

func renderGenericCmd(rc *RenderingCtx, buf *strings.Builder, cmd Cmd) error {
	var newRc RenderingCtx
	switch cmd.name {
	case SymSection:
		var anchor, title string
		if err := extractTextArgument(cmd, 0, &anchor); err != nil {
			return fmt.Errorf("failed to extract section anchor: %w", err)
		}
		if err := extractTextArgument(cmd, 1, &title); err != nil {
			return fmt.Errorf("failed to extract section title: %w", err)
		}
		if rc.sectionCounter > 0 {
			buf.WriteString("</section>")
		}
		fmt.Fprintf(buf, `<section><h2 id="%[1]s"><a href="#%[1]s">`, template.HTMLEscapeString(anchor))
		renderText(&newRc, buf, title)
		buf.WriteString("</a></h2><p>")
		rc.sectionCounter++
	case SymSubSection:
		var anchor, title string
		if err := extractTextArgument(cmd, 0, &anchor); err != nil {
			return fmt.Errorf("failed to extract subsection anchor: %w", err)
		}
		if err := extractTextArgument(cmd, 1, &title); err != nil {
			return fmt.Errorf("failed to extract subsection title: %w", err)
		}
		fmt.Fprintf(buf, `<h3 id="%[1]s"><a href="#%[1]s">`, template.HTMLEscapeString(anchor))
		renderText(&newRc, buf, title)
		buf.WriteString("</a></h3><p>")
	case SymBold:
		buf.WriteString("<b>")
		if err := renderGenericSeq(&newRc, buf, cmd.args[0]); err != nil {
			return err
		}
		buf.WriteString("</b>")
	case SymQED:
		buf.WriteRune('∎')
	case SymEmphasis:
		buf.WriteString("<em>")
		if err := renderGenericSeq(&newRc, buf, cmd.args[0]); err != nil {
			return err
		}
		buf.WriteString("</em>")
	case SymSub:
		buf.WriteString("<sub>")
		if err := renderGenericSeq(&newRc, buf, cmd.args[0]); err != nil {
			return err
		}
		buf.WriteString("</sub>")
	case SymSup:
		buf.WriteString("<sup>")
		if err := renderGenericSeq(&newRc, buf, cmd.args[0]); err != nil {
			return err
		}
		buf.WriteString("</sup>")
	case SymItem:
		switch rc.parent {
		case GenericCtx:
			return errors.New("found \\item in a non-list context")
		case UnorderedListCtx:
			buf.WriteString("<li>")
		case OrderedListCtx:
			fmt.Fprintf(buf, `<li data-num-glyph="%s">`, roundNumGlyph(rc.listCounter+1))
			rc.listCounter++
		}
	case SymSmallCaps:
		buf.WriteString(`<span class="smallcaps">`)
		if err := renderGenericSeq(&newRc, buf, cmd.args[0]); err != nil {
			return err
		}
		buf.WriteString("</span>")
	case SymLdots:
		buf.WriteRune('…')
	case SymNewline:
		buf.WriteString("<br>")
	case SymHRule:
		buf.WriteString("<hr>")
	case SymCircled:
		var n int
		if err := extractIntArgument(cmd, 0, &n); err != nil {
			return err
		}
		buf.WriteString(`<span class="circled-ref">`)
		buf.WriteString(roundNumGlyph(n))
		buf.WriteString(`</span>`)
	case SymCode:
		newRc.parent = CodeCtx
		fmt.Fprintf(buf, `<code class="%s">`, optsToCssClasses(cmd.opts))
		if err := renderGenericSeq(&newRc, buf, cmd.args[0]); err != nil {
			return err
		}
		buf.WriteString("</code>")
	case SymMath:
		buf.WriteString(`<span class="math">`)
		if err := renderGenericSeq(&newRc, buf, cmd.args[0]); err != nil {
			return err
		}
		buf.WriteString("</span>")
	case SymHref:
		var dst string
		if err := extractTextArgument(cmd, 0, &dst); err != nil {
			return fmt.Errorf("failed to extract href link: %w", err)
		}
		fmt.Fprintf(buf, `<a href="%s">`, template.HTMLEscapeString(dst))
		if err := renderGenericSeq(&newRc, buf, cmd.args[1]); err != nil {
			return err
		}
		buf.WriteString("</a>")
	case SymIncludeGraphics:
		var dst string
		if err := extractTextArgument(cmd, 0, &dst); err != nil {
			return fmt.Errorf("failed to extract includegraphics path: %w", err)
		}
		imgPath := path.Join(inputDir, dst)
		contents, err := os.ReadFile(imgPath)
		if err != nil {
			return fmt.Errorf("failed to read image at %s: %w", imgPath, err)
		}
		encoded := base64.StdEncoding.EncodeToString(contents)
		switch path.Ext(dst) {
		case ".svg":
			buf.WriteString(`<p class="svg">`)
			fmt.Fprintf(buf, `<img class="%s" src="data:image/svg+xml;base64,%s">`, optsToCssClasses(cmd.opts), encoded)
			buf.WriteString("</p>")
		case ".png":
			fmt.Fprintf(buf, `<img class="%s" src="data:image/png;base64,%s">`, optsToCssClasses(cmd.opts), encoded)
		case ".jpg", ".jpeg":
			encoded := base64.StdEncoding.EncodeToString(contents)
			fmt.Fprintf(buf, `<img class="%s" src="data:image/jpeg;base64,%s">`, optsToCssClasses(cmd.opts), encoded)
		default:
			return fmt.Errorf("unsupported image type: %s", dst)
		}
	case SymAdvice:
		var anchor string
		if err := extractTextArgument(cmd, 0, &anchor); err != nil {
			return fmt.Errorf("failed to extract %s anchor: %w", SymbolName(cmd.name), err)
		}
		fmt.Fprintf(buf, `<div class="advice" id="%[1]s"><p><a class="anchor" href="#%[1]s">☛</a>`, template.HTMLEscapeString(anchor))
		renderGenericSeq(&newRc, buf, cmd.args[1])
		buf.WriteString("</p></div>")
	case SymMarginNote:
		var anchor string
		if err := extractTextArgument(cmd, 0, &anchor); err != nil {
			return fmt.Errorf("failed to extract %s anchor: %w", SymbolName(cmd.name), err)
		}
		fmt.Fprintf(buf, `<label class="margin-toggle" for="%[1]s">⊕</label><input type="checkbox" id="%[1]s" class="margin-toggle">`, template.HTMLEscapeString(anchor))
		buf.WriteString(`<span class="marginnote">`)
		renderGenericSeq(&newRc, buf, cmd.args[1])
		buf.WriteString("</span>")
	case SymSideNote:
		var anchor string
		if err := extractTextArgument(cmd, 0, &anchor); err != nil {
			return fmt.Errorf("failed to extract %s anchor: %w", SymbolName(cmd.name), err)
		}
		fmt.Fprintf(buf, `<label class="margin-toggle sidenote-number" for="%[1]s"></label><input type="checkbox" id="%[1]s" class="margin-toggle">`, template.HTMLEscapeString(anchor))
		buf.WriteString(`<span class="sidenote">`)
		renderGenericSeq(&newRc, buf, cmd.args[1])
		buf.WriteString("</span>")
	case SymEpigraph:
		buf.WriteString(`<div class="epigraph">`)
		if err := renderBlockquote(&newRc, buf, cmd); err != nil {
			return err
		}
		buf.WriteString("</div>")
	case SymBlockquote:
		if err := renderBlockquote(&newRc, buf, cmd); err != nil {
			return err
		}
	default:
		return fmt.Errorf("unsupported command at %d: %s", cmd.pos, cmd.Name())
	}
	return nil
}

func renderBlockquote(rc *RenderingCtx, buf *strings.Builder, cmd Cmd) error {
	buf.WriteString("<blockquote><p>")
	if err := renderGenericSeq(rc, buf, cmd.args[0]); err != nil {
		return err
	}
	buf.WriteString("</p><footer>")
	if err := renderGenericSeq(rc, buf, cmd.args[1]); err != nil {
		return err
	}
	buf.WriteString("</footer></blockquote>")
	return nil
}

func renderGenericEnv(rc *RenderingCtx, buf *strings.Builder, env Env) error {
	newRc := RenderingCtx{
		parent: GenericCtx,
	}
	switch env.name {
	case SymAbstract:
		buf.WriteString(`<div class="abstract"><p>`)
		if err := renderGenericSeq(&newRc, buf, env.body); err != nil {
			return err
		}
		buf.WriteString(`</div>`)
	case SymEnumerate:
		newRc.parent = OrderedListCtx
		buf.WriteString(`<ol class="circled">`)
		if err := renderGenericSeq(&newRc, buf, env.body); err != nil {
			return err
		}
		buf.WriteString(`</ol>`)
	case SymItemize:
		newRc.parent = UnorderedListCtx
		buf.WriteString(`<ul class="arrows">`)
		if err := renderGenericSeq(&newRc, buf, env.body); err != nil {
			return err
		}
		buf.WriteString(`</ul>`)
	case SymVerbatim:
		buf.WriteString(`<pre><code class="verbatim">`)
		for _, n := range env.body {
			switch v := n.(type) {
			case Text:
				buf.WriteString(template.HTMLEscapeString(v.body))
			default:
				return fmt.Errorf("unexpected node type in verbatim environment: %s", v)
			}
		}
		buf.WriteString("</code></pre>")
	case SymCode:
		// TODO: extra newlines at the beginning/end
		newRc.parent = CodeCtx
		fmt.Fprintf(buf, `<div class="source-container"><pre class="source %s"><code>`, optsToCssClasses(env.opts))
		if err := renderGenericSeq(&newRc, buf, env.body); err != nil {
			return err
		}
		buf.WriteString("</div></pre></code>")
	case SymFigure:
		fmt.Fprintf(buf, `<figure class="%s">`, optsToCssClasses(env.opts))
		if err := renderGenericSeq(&newRc, buf, env.body); err != nil {
			return err
		}
		buf.WriteString("</figure>")
	}
	return nil
}

func roundNumGlyph(n int) string {
	return string(rune(0x245f + n))
}
