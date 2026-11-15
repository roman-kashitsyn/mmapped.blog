//! The engine of mmapped.blog.
//!
//! - [`site`] reads the sources of the site and checks them as a whole.
//! - [`report`] shows what is wrong with them.
//! - [`render`] turns documents into HTML; [`pages`] wraps them into pages.
//!
//! The syntax of the sources lives in `rftex-syntax` and their meaning in
//! `rftex-doc`; this crate adds HTML, the file system and the terminal.

mod highlight;
pub mod html;
pub mod mathml;
pub mod pages;
pub mod render;
pub mod report;
pub mod site;
