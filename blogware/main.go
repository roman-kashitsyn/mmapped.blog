package main

import (
	"flag"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"path"
	"strings"
	"time"
)

var (
	serve      string
	inputDir   string
	outputDir  string
	renderFile string
	rootURL    string
)

func getTemplate(name string) (tmpl *template.Template, err error) {
	tmpl = template.New(name)
	tmpl.Funcs(map[string]any{
		"StringsJoin": strings.Join,
		"FormatDate": func(t time.Time) string {
			return t.UTC().Format("2006-01-02")
		},
	})
	tmpl, err = tmpl.ParseGlob(path.Join(inputDir, "templates/*.tmpl"))
	if err != nil {
		log.Fatalf("Failed to parse the post template: %v", err)
	}
	return
}

func parseArticle(path string) (article Article, err error) {
	stream, err := StreamFromFile(path)
	if err != nil {
		err = fmt.Errorf("failed to read input file %s: %w", path, err)
		return
	}

	seq, err := ParseSequence(stream)
	if err != nil {
		err = fmt.Errorf("failed to parse the document: %w", err)
		return
	}

	article, err = ArticleMetadata(seq)
	if err != nil {
		err = fmt.Errorf("failed to parse article metadata: %w", err)
		return
	}
	return
}

func renderOne(inputPath string) {
	article, err := parseArticle(inputPath)
	if err != nil {
		log.Fatalf("Failed to parse article metadata: %v", err)
	}
	toc, err := article.Toc()
	if err != nil {
		log.Fatalf("Failed to parse article table of contents: %v", err)
	}
	body, err := article.RenderBody()
	if err != nil {
		log.Fatalf("Failed to render article body: %v", err)
	}
	ctx := PostRenderContext{
		Title:      article.Title,
		CreatedAt:  article.CreatedAt,
		ModifiedAt: article.ModifiedAt,
		Keywords:   article.Keywords,
		URL:        article.URL,
		RedditLink: article.RedditLink,
		Toc:        toc,
		Body:       body,
		PrevPost:   nil,
		NextPost:   nil,
	}
	tmpl, err := getTemplate("post")
	if err != nil {
		log.Fatalf("Failed to parse the template: %v", err)
	}
	start := time.Now()
	if err := tmpl.Execute(os.Stdout, ctx); err != nil {
		log.Fatalf("Failed to execute the template: %v", err)
	}
	log.Printf("Rendered %s in %s", inputPath, time.Since(start))
}

func main() {
	flag.StringVar(&serve, "serve", "", "the address to serve content on")
	flag.StringVar(&inputDir, "input", ".", "the path to the source root")
	flag.StringVar(&outputDir, "output", "", "the destination directory for static pages")
	flag.StringVar(&renderFile, "f", "", "render the specified file to stdout and exit")
	flag.StringVar(&rootURL, "root", "https://mmapped.blog", "the root URL of the blog")

	flag.Parse()

	if len(renderFile) > 0 {
		renderOne(renderFile)
		return
	}

	if len(outputDir) > 0 {
		if err := RenderSite(); err != nil {
			log.Fatalf("Failed to render site: %v", err)
		}
	}

	if len(serve) > 0 {
		log.Printf("Serving the site on %s", serve)
		RegisterHttpHandlers()
		log.Fatal(http.ListenAndServe(serve, nil))
	}
}
