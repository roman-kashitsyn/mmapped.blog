package main

import (
	"bytes"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

type AssetType int

const (
	StaticFiles AssetType = iota
	IndexPage
	TeXArticles
	StandalonePage
	PostList
	AtomXMLFeed
)

const (
	HTMLExt = ".html"
	TexExt  = ".tex"
)

const FilePerm = 0o755

type LayoutEntry struct {
	Path string
	Type AssetType
}

var SiteLayout = []LayoutEntry{
	{Path: "/css/", Type: StaticFiles},
	{Path: "/fonts/", Type: StaticFiles},
	{Path: "/images/", Type: StaticFiles},
	{Path: "/posts/", Type: TeXArticles},
	{Path: "/posts.html", Type: PostList},
	{Path: "/about.html", Type: StandalonePage},
	{Path: "/feed.xml", Type: AtomXMLFeed},
	{Path: "/index.html", Type: IndexPage},
}

func handleAtomRender(w http.ResponseWriter, _ *http.Request) {
	articles, err := AllArticles()
	if err != nil {
		w.WriteHeader(500)
		fmt.Fprintf(w, "Failed to list posts: %v", err)
		return
	}
	feed, err := RenderAtomFeed(rootURL, articles)
	if err != nil {
		w.WriteHeader(500)
		fmt.Fprintf(w, "Failed to render atom feed: %v", err)
		return
	}
	w.Header().Add("Content-Type", "application/atom+xml")
	fmt.Fprintf(w, "%s", xml.Header)
	w.Write(feed)
}

func renderPostList(title string, articles []Article) (contents []byte, err error) {
	tmpl, err := getTemplate("post-list")
	if err != nil {
		err = fmt.Errorf("failed to parse the post list template: %v", err)
		return
	}
	ctx := PostListRenderContext{
		Title:    title,
		Articles: articles,
	}
	var buf bytes.Buffer
	if err = tmpl.Execute(&buf, ctx); err != nil {
		err = fmt.Errorf("failed to execute the post list template: %v", err)
		return
	}
	contents = buf.Bytes()
	return
}

func handlePostListRender(w http.ResponseWriter, r *http.Request) {
	posts, err := AllArticles()
	if err != nil {
		w.WriteHeader(500)
		fmt.Fprintf(w, "Failed to list posts: %v", err)
		return
	}
	contents, err := renderPostList("All Posts", posts)
	if err != nil {
		w.WriteHeader(500)
		fmt.Fprintf(w, "Failed to render the post list at %s: %v", r.URL.Path, err)
		return
	}
	if _, err := w.Write(contents); err != nil {
		log.Printf("Failed to write contents for %s: %v", r.URL.Path, err)
	}
}

func renderPostAt(i int, articles []Article) (contents []byte, err error) {
	article := articles[i]
	toc, err := article.Toc()
	if err != nil {
		err = fmt.Errorf("failed to generate ToC: %v", err)
		return
	}
	body, err := article.RenderBody()
	if err != nil {
		err = fmt.Errorf("failed to render article body: %v", err)
		return
	}
	var prevPost, nextPost *Article
	if i > 0 {
		prevPost = &articles[i-1]
	}
	if i < len(articles)-1 {
		nextPost = &articles[i+1]
	}
	ctx := PostRenderContext{
		AbsoluteURL: rootURL + article.URL,
		Title:       article.Title,
		Subtitle:    article.Subtitle,
		CreatedAt:   article.CreatedAt,
		ModifiedAt:  article.ModifiedAt,
		Keywords:    article.Keywords,
		URL:         article.URL,
		Toc:         toc,
		Body:        body,
		PrevPost:    prevPost,
		NextPost:    nextPost,
	}
	tmpl, err := getTemplate("post")
	if err != nil {
		err = fmt.Errorf("failed to parse the template: %v", err)
		return
	}
	var buf bytes.Buffer
	if err = tmpl.Execute(&buf, ctx); err != nil {
		err = fmt.Errorf("failed to execute the template: %v", err)
		return
	}
	contents = buf.Bytes()
	return
}

func postsPrefix() string {
	for _, e := range SiteLayout {
		if e.Type == TeXArticles {
			return e.Path
		}
	}
	return ""
}

func handlePostRender(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == postsPrefix() {
		handlePostListRender(w, r)
		return
	}
	path := r.URL.Path
	posts, err := AllArticles()
	if err != nil {
		w.WriteHeader(500)
		fmt.Fprintf(w, "Failed to list posts: %v", err)
		return
	}
	i := slices.IndexFunc(posts, func(a Article) bool {
		return a.URL == path
	})
	if i == -1 {
		w.WriteHeader(404)
		fmt.Fprintf(w, "No post at path %s among %#v", path, posts)
		return
	}
	start := time.Now()
	bytes, err := renderPostAt(i, posts)
	log.Printf("Rendered %s in %v", path, time.Since(start))
	if err != nil {
		w.WriteHeader(500)
		fmt.Fprintf(w, "Failed to render %s: %v", path, err)
		return
	}
	if _, err := w.Write(bytes); err != nil {
		log.Printf("Failed to write the contents of %s: %v", path, err)
	}
}

func handleIndexPage(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path
	posts, err := AllArticles()
	if err != nil {
		w.WriteHeader(500)
		fmt.Fprintf(w, "Failed to list posts: %v", err)
		return
	}
	if len(posts) == 0 {
		w.WriteHeader(404)
		fmt.Fprintf(w, "No posts yet")
		return
	}
	start := time.Now()
	bytes, err := renderPostAt(0, posts)
	log.Printf("Rendered %s in %v", path, time.Since(start))
	if err != nil {
		w.WriteHeader(500)
		fmt.Fprintf(w, "Failed to render %s: %v", path, err)
		return
	}
	if _, err := w.Write(bytes); err != nil {
		log.Printf("Failed to write the contents of %s: %v", path, err)
	}
}

func renderStanalonePage(url string, htmlPath string) ([]byte, error) {
	src := strings.TrimSuffix(htmlPath, HTMLExt) + TexExt
	article, err := parseArticle(src)
	if err != nil {
		return nil, err
	}
	body, err := article.RenderBody()
	if err != nil {
		return nil, err
	}
	ctx := PageRenderContext{
		Title: article.Title,
		Body:  body,
		URL:   htmlPath,
	}
	tmpl, err := getTemplate("page")
	if err != nil {
		return nil, err
	}
	var buf bytes.Buffer
	if err = tmpl.Execute(&buf, ctx); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func handlePageRender(w http.ResponseWriter, r *http.Request) {
	src := path.Join(inputDir, r.URL.Path)
	bytes, err := renderStanalonePage(r.URL.Path, src)
	if err != nil {
		w.WriteHeader(500)
		fmt.Fprintf(w, "Failed to render this page: %v", err)
		return
	}
	if _, err := w.Write(bytes); err != nil {
		log.Printf("Failed to write the contents of %s: %v", r.URL.Path, err)
	}
}

func RegisterHttpHandlers() {
	for _, e := range SiteLayout {
		switch e.Type {
		case StaticFiles:
			http.Handle(e.Path, http.FileServer(http.Dir(inputDir)))
		case IndexPage:
			http.HandleFunc(e.Path, handleIndexPage)
		case PostList:
			http.HandleFunc(e.Path, handlePostListRender)
		case TeXArticles:
			http.HandleFunc(e.Path, handlePostRender)
		case AtomXMLFeed:
			http.HandleFunc(e.Path, handleAtomRender)
		case StandalonePage:
			http.HandleFunc(e.Path, handlePageRender)
		}
	}
}

func AllArticles() (articles []Article, err error) {
	for _, e := range SiteLayout {
		if e.Type != TeXArticles {
			continue
		}
		articlesPath := path.Join(inputDir, e.Path)
		articlesDir, osErr := os.Open(articlesPath)
		if osErr != nil {
			err = osErr
			return
		}
		defer articlesDir.Close()
		names, readnamesErr := articlesDir.Readdirnames(0)
		if readnamesErr != nil {
			err = readnamesErr
			return
		}
		slices.Sort(names)
		slices.Reverse(names)
		articles = make([]Article, 0, len(names))
		for _, name := range names {
			if path.Ext(name) != ".tex" {
				continue
			}
			article, parseErr := parseArticle(path.Join(articlesPath, name))
			if parseErr != nil {
				err = parseErr
				return
			}
			article.URL = e.Path + strings.TrimSuffix(name, TexExt) + HTMLExt
			articles = append(articles, article)
		}
		return
	}
	err = errors.New("no articles defined in the site layout")
	return
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return fmt.Errorf("failed to open %s: %w", src, err)
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return fmt.Errorf("failed to create %s: %w", dst, err)
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	if err != nil {
		return fmt.Errorf("failed to copy %s to %s: %w", src, dst, err)
	}
	return nil
}

func copyRecursively(src, dst string) error {
	return filepath.Walk(src, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if p == src {
			return nil
		}

		relPath := strings.TrimPrefix(p, src)
		dstPath := path.Join(dst, relPath)
		if info.IsDir() {
			log.Printf("Creating %s", dstPath)
			err := os.Mkdir(dstPath, 0o755)
			if os.IsExist(err) {
				return nil
			}
			return err
		} else {
			log.Printf("Copying %s => %s", p, dstPath)
			return copyFile(p, dstPath)
		}
	})
}

func RenderSite() error {
	err := os.Mkdir(outputDir, 0o755)
	if err != nil && !os.IsExist(err) {
		return fmt.Errorf("failed to create the output directory: %w", err)
	}

	articles, err := AllArticles()
	if err != nil {
		return fmt.Errorf("failed to get the article list: %w", err)
	}

	for _, e := range SiteLayout {
		src := path.Join(inputDir, e.Path)
		dst := path.Join(outputDir, e.Path)
		if strings.HasSuffix(e.Path, "/") {
			log.Printf("Creating %s", dst)
			if err := os.Mkdir(dst, 0o755); err != nil && !os.IsExist(err) {
				return fmt.Errorf("failed to create directory %s: %w", dst, err)
			}
		}

		switch e.Type {
		case StaticFiles:
			if err := copyRecursively(src, dst); err != nil {
				return fmt.Errorf("failed to copy assets from %s to %s: %w", e.Path, outputDir, err)
			}
		case IndexPage:
			log.Printf("Rendering %s", e.Path)
			contents, err := renderPostAt(0, articles)
			if err != nil {
				return fmt.Errorf("failed to render page %s: %w", e.Path, err)
			}
			postDst := path.Join(outputDir, e.Path)
			if err := os.WriteFile(postDst, contents, FilePerm); err != nil {
				return fmt.Errorf("failed to write to %s: %w", postDst, err)
			}
		case TeXArticles:
			for i := range articles {
				log.Printf("Rendering %s", articles[i].URL)
				contents, err := renderPostAt(i, articles)
				if err != nil {
					return fmt.Errorf("failed to render article %s: %w", articles[i].URL, err)
				}
				postDst := path.Join(outputDir, articles[i].URL)
				if err := os.WriteFile(postDst, contents, FilePerm); err != nil {
					return fmt.Errorf("failed to write to %s: %w", postDst, err)
				}
			}
		case StandalonePage:
			log.Printf("Rendering %s", e.Path)
			contents, err := renderStanalonePage(e.Path, src)
			if err != nil {
				return fmt.Errorf("failed to render article %s: %w", e.Path, err)
			}
			postDst := path.Join(outputDir, e.Path)
			if err := os.WriteFile(postDst, contents, FilePerm); err != nil {
				return fmt.Errorf("failed to write to %s: %w", postDst, err)
			}
		case PostList:
			log.Printf("Rendering %s", e.Path)
			contents, err := renderPostList("All Posts", articles)
			if err != nil {
				return fmt.Errorf("failed to render the post list: %w", err)
			}
			if err := os.WriteFile(dst, contents, FilePerm); err != nil {
				return fmt.Errorf("failed to write the post list to %s: %w", dst, err)
			}
		case AtomXMLFeed:
			log.Printf("Rendering %s", e.Path)
			feed, err := RenderAtomFeed(rootURL, articles)
			if err != nil {
				return fmt.Errorf("failed to render the atom feed: %w", err)
			}
			if err := os.WriteFile(dst, feed, FilePerm); err != nil {
				return fmt.Errorf("failed to write the atom feed to %s: %w", dst, err)
			}
		}
	}
	return nil
}
