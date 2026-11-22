//! The engine of mmapped.blog.
//!
//! - [`site`] reads the sources of the site and checks them as a whole.
//! - [`report`] shows what is wrong with them.
//! - [`render`] turns documents into HTML; [`pages`] wraps them into pages.
//! - [`feed`] writes the Atom feed.
//! - [`build`] writes the whole site to a directory.
//! - [`serve`] renders it page by page for a browser, while it is written.
//!
//! The syntax of the sources lives in `rftex-syntax` and their meaning in
//! `rftex-doc`; this crate adds HTML, the file system and the terminal.

pub mod build;
pub mod feed;
mod highlight;
pub mod html;
pub mod mathml;
pub mod pages;
pub mod render;
pub mod report;
pub mod serve;
pub mod site;
