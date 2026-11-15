//! The engine of mmapped.blog.
//!
//! - [`site`] reads the sources of the site and checks them as a whole.
//! - [`report`] shows what is wrong with them.
//!
//! The syntax of the sources lives in `rftex-syntax` and their meaning in
//! `rftex-doc`; this crate adds the file system and the terminal.

pub mod report;
pub mod site;
