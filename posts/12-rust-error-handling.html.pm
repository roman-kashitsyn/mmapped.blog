#lang pollen

◊(define-meta title "Designing error types in Rust")
◊(define-meta keywords "rust")
◊(define-meta summary "An optinionated guide to designing good error types in Rust.")
◊(define-meta doc-publish-date "2021-11-10")
◊(define-meta doc-updated-date "2021-11-10")

◊section{
◊section-title["introduction"]{Introduction}
◊p{
  If I had to pick one Rust feature that I like the most, that would be the systematic approach to error handling.
  Sum types, generics (such as ◊code{Result<T, E>}), and a holistic standard library design form a perfect match for my obsession with edge cases.
  Rust error handling is so good that even ◊a[#:href "https://haskell.org/"]{Haskell} looks bleak and woefully unsafe in comparison.
  This article explains how I approach errors when I design interfaces in Rust.
}
}

◊section{
◊section-title["library-vs-apps"]{Libraries vs. applications}
◊p{

}
}

◊section{
◊section-title["rules-of-thumb"]{Rules of thumb}
◊p{
  Most issues in the error type design stem from the same root: making error ◊em{propagation} easier than error ◊em{handling}.
  So all the strategies I describe in this article are a special case of the following mantra:
}
◊advice["empathy"]{
  Be empathetic to the user.
}
◊p{
  Imagine yourself having to handle the error.
  Could you write robust code given the error type and its documentation?
  Could you display an error message in a language that the end user can understand (such as German, French, or ◊a[#:href "https://en.wikipedia.org/wiki/Lojban"]{Lojban})?
}

◊subsection-title["prefer-specific-enums"]{Prefer specific enums}

◊p{
  If you came to Rust from another language, it is tempting to apply familiar error handling techniques.
  If you wrote a lot of ◊a[#:href "https://go.dev"]{Go}, you might be content with type-erased errors from the ◊a[#:href "https://crates.io/crates/anyhow"]{◊code{anyhow}} package.
}
◊source-code["bad"]{
pub fn frobnicate(n: u64) -> anyhow::Result<String> { /* ◊ellipsis{} */ }
}
◊p{
  If you hardened your character with C++ or spent a lot of time working with ◊a[#:href "https://grpc.github.io/grpc/core/md_doc_statuscodes.html"]{grpc}, having a humongous global error type might seem like a good idea.
}
◊figure{
◊marginnote["mn-typical-cpp"]{
  A typical approach to error handling in large C and C++ codebases that do not rely on exceptions is to define a humongous enum with all possible error cases.
}
◊source-code["bad"]{
pub enum ProjectWideError {
  InvalidInput,
  DatabaseConnectionError,
  Unauthorized,
  FileNotFound,
  ◊em{// ◊ellipsis{}}
}

pub fn frobnicate(n: u64) -> Result<String, ProjectWideError> { /* ◊ellipsis{} */ }
}
}

◊p{
  These approaches might work fine for you, but I found them unsatisfactory in the long run: they facilitate ◊em{propagating} errors, not ◊em{handling} errors.
}
◊p{
  When it comes to interface clarity and simplicity, nothing beats ◊a[#:href "https://en.wikipedia.org/wiki/Algebraic_data_type"]{algebraic data types} (◊smallcaps{adt}s).
  Let us use the power of ◊smallcaps{adt}s to fix the ◊code{frobnicate} function interface.
}

◊figure{
◊marginnote["mn-adt-frobnicate"]{
  Idiomatic error types for the ◊code{frobnicate} function example.
}
◊source-code["good"]{
pub enum FrobnicateError {
  ◊em{/// Frobnicate does not accept inputs above this number.}
  InputExceeds(u64),
  ◊em{/// Frobnicate cannot work on mondays. Court order.}
  CannotFrobnicateOnMondays,
}

pub fn frobnicate(n: u64) -> Result<String, FrobnicateError> { /* ◊ellipsis{} */ }
}
}

◊p{
  Now the type system tells the readers what exactly can go wrong, and it makes ◊em{handling} the errors a breeze.
}
◊p{
  You might think, ◊quoted{I will never finish my project if I define a new enum for each function that can fail}.
  In my experience, expressing failures using the type system takes less work than documenting all the quirks of the interface.
  Good types make writing good documentation easier.
  They are also worth they weight in gold when you get to testing your code.
}
◊p{
  Do not be afraid to introduce distinct error types for each function you implement.
  I am yet to find code that went overboard with types.
}

◊source-code["good"]{
#[test]
fn test_unfrobnicatable() {
  assert_eq!(FrobnicateError::InputExceeds(MAX_FROB_INPUT), frobnicate(u64::MAX));
}

#[test]
fn test_frobnicate_mondays() {
  sleep_until(next_monday());
  assert_eq!(FrobnicateError::CannotFrobnicateOnMondays, frobnicate(0));
}
}

◊subsection-title["implement-std-error"]{Implement std::error::Error}
◊p{
  Implementing the ◊a[#:href "https://doc.rust-lang.org/std/error/trait.Error.html"]{◊code{std::error::Error}} trait for error types is like being polite.
  You should do it even if you do not mean it.
}
◊p{
  Some callers might not care about your beautiful design, they will showel your error into a ◊code{Box<Error>} or ◊code{anyhow::Result} and move on.
  Maybe they are building a little command line tool that does not need to handle ◊a[#:href "https://xkcd.com/619/"]{machines with 4096 CPUs}.
  If you implement ◊code{std::error::Error} for your error types, you will make their lives a bit easier.
}
◊p{
  If you find that implementing the ◊code{std::error::Error} trait is too much work, try the ◊a[#:href "https://crates.io/crates/thiserror"]{◊code{thiserror}} package.
}

◊figure{
◊marginnote["mn-thiserror"]{
  Using the ◊a[#:href "https://crates.io/crates/thiserror"]{◊code{thiserror}} package to simplify the implementation of ◊a[#:href "https://doc.rust-lang.org/std/error/trait.Error.html"]{◊code{std::error::Error}} trait.
}
◊source-code["good"]{
use thiserror::Error;

#[derive(Error, Debug)]
pub enum FrobnicateError {
  #[error("cannot not frobnicate numbers above {0}")]
  InputExceeds(u64),

  #[error("thy shall not frobnicate on mondays (court order)")]
  CannotFrobnicateOnMondays,
}
}
}

◊subsection-title["errors-problem-vs-solution"]{Define errors in terms of the problem, not a solution}
◊p{
  The most common shape of errors I see looks like the following:
}
◊figure{
◊marginnote["mn-fetch-tx-nested"]{
  A common approch to error handling for functions with complex call graphs:
  the function error type wraps error types of all dependencies.
}
◊source-code["bad"]{
pub enum FetchTxError {
  IoError(std::io::Error),
  HttpError(http2::Error),
  SerdeError(serde_cbor::Error),
  OpensslError(openssl::ssl::Error),
}

pub fn fetch_signed_transaction(
  id: Txid,
  pk: Pubkey,
  algorithm: SignatureAlgorithm,
) -> Result<Option<Tx>, FetchTxError> { /* ◊ellipsis{} */ }
}
}

◊p{
  This error type does not tell the caller ◊em{what} problem you are solving, but rather ◊em{how} you solve it.
  Implementation details leak into the caller's code, causing much pain:
}

◊ul[#:class "arrows"]{
 ◊li{
   Such error types encourage unhealthy coding patterns when low-level errors travel up the call stack with very little context attached.
   The following error message comes from a program that often leaves me puzzled and depressed.
   ◊source-code["bad"]{
   IO error: Os { code: 2, kind: NotFound, message: "No such file or directory" }
   }
 }
 ◊li{
   Your clients have to read the documentation of the leaked dependencies to learn about possible error cases.
   Look at ◊a[#:href "https://docs.rs/openssl/0.10.42/openssl/ssl/struct.Error.html"]{◊code{openssl::ssl::Error}}, for example.
   Can you come up with a good recovery strategy without knowing what ◊code{openssl} library function returned this error?
 }
 ◊li{
   Your clients must add ◊code{openssl} and ◊code{serde_cbor} to direct dependencies to handle your errors.
   If you decide to switch from ◊code{openssl} to ◊code{libressl}, your clients will have to adapt their code.
 }
}

◊p{
  Let us redesign the ◊code{FetchTxError} type, this time focusing on the well-being of fellow programmers calling our code.
}

◊figure{
◊marginnote["mn-fetch-tx-refactoring"]{
  Idiomatic error types for the ◊code{fetch_signed_transaction} function example.
  ◊code{FetchTxError} type constructors express failure cases in terms of the problem domain, not in terms of a specific solution.
  Note the lack of external dependencies in the types.
}
◊source-code["good"]{
pub enum FetchTxError {
  ◊em{/// Could not connect to the server.}
  ConnectionFailed {
    url: String,
    reason: String,
    cause: Option<std::io::Error>, // ◊circled-ref[1]
  },

  ◊em{/// Cannot find transaction with the specified txid.}
  TxNotFound(Txid), // ◊circled-ref[2]

  ◊em{/// The object data is not valid CBOR.}
  InvalidEncoding { // ◊circled-ref[3]
    data: Bytes,
    error_offset: Option<usize>,
    error_message: String,
  },

  ◊em{/// The transaction body does not match the Txid.}
  ◊em{/// Most likely, the peer tampered with the data.}
  TxidMismatch { // ◊circled-ref[4]
    txid: Txid,
    body: Bytes,
  },

  ◊em{/// The signature on the object signature not match the public key.}
  SignatureVerificationFailed { // ◊circled-ref[4]
    txid: Txid,
    pk: Pubkey,
    sig: Signature,
  },
}

pub fn fetch_signed_transaction(
  id: Txid,
  pk: Pubkey,
  algorithm: SignatureAlgorithm,
) -> Result<Tx, FetchTxError> { /* ◊ellipsis{} */ }
}
}

◊p{The new design offers a number of improvements:}
◊ol-circled{
  ◊li{
    The ◊code{ConnectionFailed} constructor wraps a low-level ◊code{std::io::Error} error.
    The wrapping does not cause trouble because there is enough context to understand what went wrong.
  }
  ◊li{
    We replaced the ◊code{Option} type with an explicit error constructor, ◊code{TxNotFound}, clarifying the meaning of the ◊code{None} case.
  }
  ◊li{
    The ◊code{InvalidEncoding} constructor hides the details of the decoding library we use.
    We can now replace ◊code{serde_cbor} without breaking other people's code.
  }
  ◊li{
    We replaced generic crypto errors with two specific cases: ◊code{TxidMismatch} and ◊code{SignatureVerificationFailed}.
    Our fellow programmer has more context to make rational decisions: ◊code{TxidMismatch} indicates that we should try again with another peer, while ◊code{SignatureVerificationFailed} indicates that the end user supplied a wrong public key.
  }
}

◊p{
  If I needed to call ◊code{fetch_signed_transaction}, I would prefer the latter interface.
  Which interface would you prefer?
  Which interface will be easier to test?
}

◊subsection-title["embed-not-wrap"]{Do not wrap errors, embed them}

◊p{
  We have already seen the tactic of embedding error cases in the previous section.
  This tactic eases interface comprehension so much that it deserves more attention.
}

◊p{
  Imagine that we are working on a little library that verifies cryptographic signatures.
}

◊source-code["bad"]{
pub enum VerifySigError {
  EcdsaError { source: ecdsa::Error, context: String },
  BlsError { source: bls12_381_sign::Error, context: String },
}

pub fn verify_sig(
  algo: Algorithm,
  pk: Bytes,
  sig: Bytes,
  msg_hash: Hash,
) -> Result<(), VerifySigError> { /* ◊ellipsis{} */ }
}

◊source-code["good"]{
pub enum VerifySigError {
  MalformedPublicKey { pk: Bytes, reason: String },
  MalformedSignature { sig: Bytes, reason: String },
  SignatureVerificationFailed {
    algo: Algorithm,
    pk: Bytes,
    sig: Bytes,
    reason: String
  },
  // ◊ellipsis{}
}

pub fn verify_sig(
  algo: Algorithm,
  pk: Bytes,
  sig: Bytes,
  msg_hash: Hash,
) -> Result<(), VerifySigError> { /* ◊ellipsis{} */ }
}

◊p{
  There are a few exceptions:
}
◊ul[#:class "arrows"]{
  ◊li{
    Wrapping ◊code{std::io::Error} is acceptable as long as you include enough additional context, such as the attempted operation and the paths involved.
    ◊code{std::io::Error} does not bring extra dependencies and is familiar to any seasoned Rust programmer, so it adds little cognitive load.
  }
  ◊li{
    It's usually fine to convert lower-level errors to string and attach this string to your errors, as long as the containing constructor is descriptive enough and has enough context.
  }
}
}

◊section{
◊section-title["resources"]{Resources}
◊p{
  There is a lot of research on error handling approaches, yet the practial application of those ideas in real-world programming interfaces is an art requiring good taste and human compassion.
  The following resources made the deepest imprint in my thinking about errors.
}
◊ol-circled{
  ◊li{◊a[#:href "https://web.archive.org/web/20110818020758/http://www.univ-orleans.fr/lifo/Members/David.Teller/publications/ml2008.pdf"]{Catch me if you can: Looking for type-safe, hierarchical, lightweight, polymorphic and efficient error management in OCaml} by David Teller, Arnaud Spiwack, and Till Varoquaux.}
  ◊li{◊a[#:href "https://www.parsonsmatt.org/2018/11/03/trouble_with_typed_errors.html"]{The Trouble with Typed Errors} by Matt Parsons.}
  ◊li{The ◊a[#:href "https://wiki.haskell.org/Error_vs._Exception"]{Error vs. Exception} article on Haskell Wiki.}
}
}
