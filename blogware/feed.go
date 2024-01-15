package main

import (
	"encoding/xml"
	"net/url"
	"time"
)

type AtomFeedCategory struct {
	Term string `xml:"term,attr"`
}

type AtomFeedLink struct {
	Rel  string `xml:"rel,attr,omitempty"`
	Href string `xml:"href,attr"`
}

type AtomFeedAuthor struct {
	Name string `xml:"name"`
}

type AtomFeedEntry struct {
	ID         string             `xml:"id"`
	Author     AtomFeedAuthor     `xml:"author"`
	Title      string             `xml:"title"`
	Link       AtomFeedLink       `xml:"link"`
	Summary    string             `xml:"summary"`
	Published  string             `xml:"published"`
	Updated    string             `xml:"updated"`
	Categories []AtomFeedCategory `xml:"category"`
}

type AtomFeed struct {
	XMLName xml.Name        `xml:"feed"`
	Xmlns   string          `xml:"xmlns,attr"`
	Lang    string          `xml:"xml:lang,attr"`
	Title   string          `xml:"title"`
	ID      string          `xml:"id"`
	Updated string          `xml:"updated"`
	Link    AtomFeedLink    `xml:"link"`
	Author  AtomFeedAuthor  `xml:"author"`
	Entries []AtomFeedEntry `xml:"entry"`
}

func RenderAtomFeed(rootURL string, articles []Article) ([]byte, error) {
	entries := make([]AtomFeedEntry, 0, len(articles))
	var lastUpdated time.Time
	author := AtomFeedAuthor{Name: "Roman Kashitsyn"}
	for _, article := range articles {
		if article.ModifiedAt.After(lastUpdated) {
			lastUpdated = article.ModifiedAt
		}
		categories := make([]AtomFeedCategory, 0, len(article.Keywords))
		for _, kw := range article.Keywords {
			categories = append(categories, AtomFeedCategory{Term: kw})
		}
		entryURL, err := url.Parse(rootURL + article.URL)
		if err != nil {
			return nil, err
		}
		entries = append(entries, AtomFeedEntry{
			ID:         entryURL.String(),
			Link:       AtomFeedLink{Href: entryURL.String()},
			Author:     author,
			Title:      article.Title,
			Summary:    article.Subtitle,
			Published:  article.CreatedAt.UTC().Format(time.RFC3339),
			Updated:    article.ModifiedAt.UTC().Format(time.RFC3339),
			Categories: categories,
		})
	}
	feed := AtomFeed{
		Xmlns:   "http://www.w3.org/2005/Atom",
		Lang:    "en-us",
		Title:   "MMapped blog",
		ID:      rootURL,
		Link:    AtomFeedLink{Href: rootURL + "/feed.xml", Rel: "self"},
		Author:  author,
		Updated: lastUpdated.UTC().Format(time.RFC3339),
		Entries: entries,
	}
	return xml.Marshal(&feed)
}
