#lang pollen

◊(define-meta title "Designing error types in Rust")
◊(define-meta keywords "rust")
◊(define-meta summary "An optinionated guide to designing humane error types in Rust.")
◊(define-meta doc-publish-date "2022-11-15")
◊(define-meta doc-updated-date "2022-11-15")

◊section{
◊section-title["introduction"]{Introduction}
◊p{
  If I had to pick my favorite ◊a[#:href "https://www.rust-lang.org/"]{Rust language} feature, that would be its systematic approach to error handling.
  Sum types, generics (such as ◊a[#:href "https://doc.rust-lang.org/std/result/enum.Result.html"]{◊code{Result<T, E>}}), and a holistic standard library design perfectly◊sidenote["sn-polimorphic-variants"]{◊em{Almost} perfectly: I miss ◊a[#:href "https://dev.realworldocaml.org/variants.html#scrollNav-4"]{polymorphic variants} badly.} match my obsession with edge cases.
  Rust error handling is so good that even ◊a[#:href "https://haskell.org/"]{Haskell} looks bleak and woefully unsafe◊sidenote["sn-haskell-exceptions"]{
    Haskell can replicate Rust's approach to error handling, but the standard library chose the route of runtime exceptions, and ◊a[#:href "https://www.fpcomplete.com/haskell/tutorial/exceptions/"]{practitioners} followed the lead.
  }.
  This article explains how I approach errors when I design library interfaces in Rust.
}
}

◊section{
◊section-title["library-vs-apps"]{Libraries vs. applications}
◊p{
  My approach to errors differs depending on whether I am writing a general-purpose library, a background daemon, or a command-line tool.
}
◊p{
  Applications interface humans.
  Applications do their job well when they resolve issues without human intervention or, if automatic recovery is impossible or undesirable, provide the user with a clear explanation of how to resolve the issue.
}
◊p{
  Library code interfaces other code.
  Libraries do their job well when they recover from errors transparently and provide programmers with a complete list of error cases from which they cannot recover.
}
◊p{
  This guide targets library design because that is the area with which I am most familiar.
  However, the core ◊a[#:href "empathy"]{principle of empathy} applies equally well to designing machine-machine, human-machine, and human-human interfaces.
}
}

◊section{
◊section-title["design-heuristics"]{Design heuristics}
◊p{
  Most issues in the error type design stem from the same root: making error cases easy for the code author at the expense of the caller.
  All the strategies I describe in this article are applications of the following mantra:
}
◊advice["empathy"]{
  Be empathetic to your user.
}
◊p{
  Imagine yourself having to handle the error.
  Could you write robust code given the error type and its documentation?
  Could you translate the error into a message the end user can understand?
}

◊subsection-title["prefer-specific-enums"]{Prefer specific enums}

◊p{
  Applying familiar error-handling techniques is tempting if you come to Rust from another language.
  A single error type might seem natural if you wrote a lot of ◊a[#:href "https://go.dev"]{Go}.
}
◊figure{
◊marginnote["mn-anyhow"]{
  Implementing a Go-like approach to error handling using the ◊a[#:href "https://crates.io/crates/anyhow"]{◊code{anyhow}} package.
}
◊source-code["bad"]{
pub fn frobnicate(n: u64) -> anyhow::Result<String> { /* ◊ellipsis{} */ }
}
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
  These approaches might work fine for you, but I found them unsatisfactory for library design◊sidenote["sn-anyhow"]{
    However, I often use the ◊code{anyhow} approach to simplify structuring errors in command-line tools and daemons.
  } in the long run: they facilitate ◊em{propagating} errors (often with little context about the operation that caused the error), not ◊em{handling} errors.
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
  Now the type system tells the readers what exactly can go wrong, making ◊em{handling} the errors a breeze.
}
◊p{
  You might think, ◊quoted{I will never finish my project if I define a new enum for each function that can fail}.
  In my experience, expressing failures using the type system takes less work than documenting all the quirks of the interface.
  Specific types make writing good documentation easier.
  They repay their weight in gold when you start testing your code.
}
◊p{
  Feel free to introduce distinct error types for each function you implement.
  I am still looking for Rust code that went overboard with distinct error types.
}

◊figure{
◊marginnote["mn-testing-frobnicate"]{
  Specific error types at work: writing test cases becomes more enjoyable.
}
◊source-code["good"]{
#[test]
fn test_unfrobnicatable() {
  assert_eq!(FrobnicateError::InputExceeds(MAX_FROB_INPUT), frobnicate(u64::MAX));
}

#[test]
fn test_frobnicate_on_mondays() {
  sleep_until(next_monday());
  assert_eq!(FrobnicateError::CannotFrobnicateOnMondays, frobnicate(0));
}
}
}

◊subsection-title["avoid-panics"]{Reserve panics for bugs in your code}
◊epigraph{
◊blockquote[#:cite "https://doc.rust-lang.org/std/macro.panic.html#when-to-use-panic-vs-result"]{
  ◊p{
    The ◊code{panic!} macro is used to construct errors that represent a bug that has been detected in your program. 
  }
  ◊footer{The Rust Standard Library, ◊a[#:href "https://doc.rust-lang.org/std/macro.panic.html#when-to-use-panic-vs-result"]{When to use ◊code{panic!} vs ◊code{Result}}.}
}
}
◊p{
  The primary purpose of ◊a[#:href "https://doc.rust-lang.org/std/macro.panic.html"]{◊code{panics}} in Rust is to indicate bugs in your program.
  Resist the temptation to use panics for input validation, even if you document panics meticulously.
  People rarely read documentation and they can easily miss your warnings.
  Use the type system to guide them.
}
◊figure{
◊marginnote["mn-panic-doc"]{
  A library function relying on documentation to specify correct inputs.
}
◊source-code["bad"]{
◊em{
/// Frobnicates an integer.
///
/// ◊b{# Panics}
///
/// This function panics if
/// * the `n` argument is greater than [MAX_FROB_INPUT].
/// * you call it on Monday.
}
pub fn frobnicate(n: u64) -> String { /* ◊ellipsis{} */ }
}
}
◊p{
  Feel free to use panics and assertions to check invariants that must hold in ◊em{your} code.
}
◊figure{
◊marginnote["mn-panic-doc"]{
  Using assertions to check invariants and post-conditions.
}
◊source-code["good"]{
pub fn remove_from_tree<K: Ord, V>(tree: &mut Tree<K, V>, key: &K) -> Option<V> {
  let maybe_value = /* ◊ellipsis{} */;
  ◊b{debug_assert!}(tree.balanced());
  ◊b{debug_assert!}(!tree.contains(key));
  maybe_value
}
}
}

◊subsection-title["lift-input-validation"]{Lift input validation}
◊p{
  Good functions do not panic on invalid inputs.
  Great functions do not have to validate inputs.
  Let us consider the following interface of a function that sends an email.
}

◊figure{
◊marginnote["mn-input-validation"]{
  The ◊code{send_mail} function validates email addresses and sends emails.
}
◊source-code["bad"]{
pub enum SendMailError {
  ◊em{/// One of the addresses passed to ◊code{send_mail} is invalid.}
  ◊b{MalformedAddress} { address: String, reason: String },
  ◊em{/// Failed to connect to the mail server.}
  FailedToConnect { source: std::io::Error, reason: String },
  /* ◊ellipsis{} */

}
pub fn send_mail(to: &str, cc: &[&str], body: &str) -> SendMailError { /* ◊ellipsis{} */ }
}
}

◊p{
  Note that our ◊code{send_mail} function does at least two things: validating email addresses and sending emails.
  Such a state of affairs becomes tiresome if you have many functions that expect valid addresses as inputs.
  One solution is to pepper the code with more types.
  In this case, we can introduce the ◊code{EmailAddress} type that holds only valid email addresses.
}

◊figure{
◊marginnote["mn-input-validation-type"]{
  Introducing a new type to make ◊code{send_mail} inputs valid by construction.
}
◊source-code["good"]{
◊em{/// Represents valid email addresses}.
pub struct EmailAddress(String);

impl std::str::FromStr for EmailAddress {
  type Err = ◊b{MalformedEmailAddress};
  fn from_str(s: &str) -> Result<Self, Self::Err> { /* ◊ellipsis{} */ }
}

pub enum SendMailError {
  ◊em{// no more InvalidAddress!}
  FailedToConnect { source: std::io::Error, reason: String },
  /* ◊ellipsis{} */
}

pub fn send_mail(to: &EmailAddress, cc: &[&EmailAddress], body: &str) -> SendMailError { /* ◊ellipsis{} */ }
}
}

◊p{
  If we add more functions working with valid addresses, these functions will not have to run the validation logic and return address validation errors.
  We also enable the caller to perform address validation earlier, closer to where the program receives that address.
}

◊subsection-title["implement-std-error"]{Implement std::error::Error}
◊p{
  Implementing the ◊a[#:href "https://doc.rust-lang.org/std/error/trait.Error.html"]{◊code{std::error::Error}} trait for error types is like being polite.
  You should do it even if you do not mean it.
}
◊p{
  Some callers might care about something other than your beautiful design, shoveling your errors into a ◊code{Box<Error>} or ◊code{anyhow::Result} and moving on.
  They may be building a little command line tool that does not need to handle ◊a[#:href "https://xkcd.com/619/"]{machines with 4096 CPUs}.
  If you implement ◊code{std::error::Error} for your error types, you will make their lives easier.
}
◊p{
  If you find that implementing the ◊code{std::error::Error} trait is too much work, try using the ◊a[#:href "https://crates.io/crates/thiserror"]{◊code{thiserror}} package.
}

◊figure{
◊marginnote["mn-thiserror"]{
  Using the ◊a[#:href "https://crates.io/crates/thiserror"]{◊code{thiserror}} package to simplify the implementation of the ◊a[#:href "https://doc.rust-lang.org/std/error/trait.Error.html"]{◊code{std::error::Error}} trait.
}
◊source-code["good"]{
use thiserror::Error;

#[derive(Error, Debug)]
pub enum FrobnicateError {
  #[error("cannot frobnicate numbers above {0}")]
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
  the result error type wraps error types of all dependencies.
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
  pk: &[u8],
) -> Result<Option<Tx>, FetchTxError> { /* ◊ellipsis{} */ }
}
}

◊p{
  This error type does not tell the caller ◊em{what} problem you are solving but ◊em{how} you solve it.
  Implementation details leak into the caller's code, causing much pain:
}

◊ul[#:class "arrows"]{
 ◊li{
   Such error types encourage unhealthy coding patterns when low-level errors travel up the call stack with minimal context attached.
   The following error message comes from one program I have to use that often leaves me puzzled and depressed.
   ◊source-code["bad"]{
   IO error: Os { code: 2, kind: NotFound, message: "No such file or directory" }
   }
 }
 ◊li{
   Your clients must read the leaked dependencies documentation to learn about possible error cases.
   Look at ◊a[#:href "https://docs.rs/openssl/0.10.42/openssl/ssl/struct.Error.html"]{◊code{openssl::ssl::Error}}, for example.
   Can you devise a good recovery strategy without knowing which ◊code{openssl} library function returned this error?
 }
 ◊li{
   Your clients must add ◊code{openssl} and ◊code{serde_cbor} to direct dependencies to handle your errors.
   If you decide to switch from ◊code{openssl} to ◊code{libressl} or from ◊code{serde_cbor} to ◊code{ciborium}, your clients will have to adapt their code.
 }
}

◊p{
  Let us redesign the ◊code{FetchTxError} type, focusing on the well-being of fellow programmers calling that code.
}

◊figure{
◊marginnote["mn-fetch-tx-refactoring"]{
  Idiomatic error types for the ◊code{fetch_signed_transaction} function example.
  ◊code{FetchTxError} type constructors express failure cases in terms of the problem domain, not a specific solution.
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

  ◊em{/// The public key is malformed.}
  MalformedPublicKey { // ◊circled-ref[4]
    key_bytes: Vec<u8>,
    reason: String,
  },

  ◊em{/// The transaction signature does not match the public key.}
  SignatureVerificationFailed { // ◊circled-ref[4]
    txid: Txid,
    pk: Pubkey,
    sig: Signature,
  },
}

pub fn fetch_signed_transaction(
  id: Txid,
  pk: &[u8],
) -> Result<Tx, FetchTxError> { /* ◊ellipsis{} */ }
}
}

◊p{The new design offers several of improvements:}
◊ol-circled{
  ◊li{
    The ◊code{ConnectionFailed} constructor wraps a low-level ◊code{std::io::Error} error.
    Wrapping works fine here because there is enough context to understand what went wrong.
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
    Our fellow programmer has more context to make rational decisions: the ◊code{MalformedPublicKey} case indicates that the user supplied the wrong key.
    The ◊code{SignatureVerificationFailed} case can indicate that the peer tampered with the data, so we should try connecting to another peer.
  }
}

◊p{
  If I needed to call ◊code{fetch_signed_transaction}, I prefer the latter interface.
  Which interface would you choose?
  Which interface will be easier to test?
}

◊subsection-title["embed-not-wrap"]{Do not wrap errors, embed them}

◊p{
  We have already seen the tactic of embedding error cases in the previous section.
  This tactic eases interface comprehension so much that it deserves more attention.
}

◊p{
  Imagine that we are working on a little library that verifies cryptographic signatures.
  We want to support ◊a[#:href "https://en.wikipedia.org/wiki/Elliptic_Curve_Digital_Signature_Algorithm"]{ECDSA} and ◊a[#:href "https://en.wikipedia.org/wiki/BLS_digital_signature"]{BLS} signatures.
  We start from the path of the least resistance.
}

◊figure{
◊marginnote["mn-verify-sig-bad"]{
  The signature verification function interface that wraps errors from third-party libraries.
}
◊source-code["bad"]{
pub enum Algorithm { Ecdsa, Bls12381 };

pub enum VerifySigError {
  EcdsaError { source: ecdsa::Error, context: String },
  BlsError { source: bls12_381_sign::Error, context: String },
}

pub fn verify_sig(
  algorithm: Algorithm,
  pk: Bytes,
  sig: Bytes,
  msg_hash: Hash,
) -> Result<(), VerifySigError> { /* ◊ellipsis{} */ }
}
}

◊p{
  There are a few issues with that ◊code{verify_sig} function design.
}
◊ul[#:class "arrows"]{
  ◊li{
    There is an implicit assumption that if the caller passes the ◊code{Ecdsa} as the ◊code{algorithm}, the error can be only ◊code{EcdsaError}.
    It should be clear from the semantics, but the type system does not enforce this invariant.
  }
  ◊li{
    The error type leaks implementation details to the caller.
  }
  ◊li{
    If we extend the list of supported algorithms, the caller might have to modify all call sites.
  }
}
◊p{
  We can address these issues by removing one layer of nesting and embedding error cases from ◊code{ecdsa::Error} and ◊code{bls12_381_sign::Error} into the ◊code{VerifySigError} error type.
  The result is a clear and self-descriptive error type conveying to your callers that you care about them.
}

◊figure{
◊marginnote["mn-verify-sig-good"]{
  The signature verification function interface embedding and deduplicating error cases coming from third-party libraries.
}
◊source-code["good"]{
pub enum Algorithm { Ecdsa, Bls12381 };

pub enum VerifySigError {
  MalformedPublicKey { pk: Bytes, reason: String },
  MalformedSignature { sig: Bytes, reason: String },
  SignatureVerificationFailed {
    algorithm: Algorithm,
    pk: Bytes,
    sig: Bytes,
    reason: String
  },
  // ◊ellipsis{}
}

pub fn verify_sig(
  algorithm: Algorithm,
  pk: Bytes,
  sig: Bytes,
  msg_hash: Hash,
) -> Result<(), VerifySigError> { /* ◊ellipsis{} */ }
}
}

◊p{
  There are a few cases when wrapping errors makes sense:
}
◊ul[#:class "arrows"]{
  ◊li{
    Wrapping ◊code{std::io::Error} is acceptable if you include enough context, such as the attempted operation and the paths involved.
    ◊code{std::io::Error} does not bring extra dependencies and is familiar to any seasoned Rust programmer, so it adds little cognitive load.
    ◊code{std::io::Error}s also can contain low-level ◊a[#:href "https://doc.rust-lang.org/std/io/struct.Error.html#method.raw_os_error"]{OS error codes} that can help diagnose tricky cases.
  }
  ◊li{
    It is often acceptable to convert a lower-level error to a string and attach that string to your errors, as long as the containing error type constructor is descriptive enough.
    However, you should check that these strings do not contain sensitive information, such as email addresses or secret keys.
  }
}

}

◊section{
◊section-title["resources"]{Resources}
◊p{
  There is a lot of research on error-handling approaches.
  Yet the practical application of those ideas in real-world programming interfaces is an art requiring good taste and human compassion.
  The following resources made the most profound imprint on my thinking about errors.
}
◊ol-circled{
  ◊li{◊a[#:href "https://web.archive.org/web/20110818020758/http://www.univ-orleans.fr/lifo/Members/David.Teller/publications/ml2008.pdf"]{Catch me if you can: Looking for type-safe, hierarchical, lightweight, polymorphic and efficient error management in OCaml} by David Teller, Arnaud Spiwack, and Till Varoquaux.}
  ◊li{The ◊a[#:href "https://wiki.haskell.org/Error_vs._Exception"]{Error vs. Exception} article on Haskell Wiki.}
  ◊li{◊a[#:href "https://www.parsonsmatt.org/2018/11/03/trouble_with_typed_errors.html"]{The Trouble with Typed Errors} by Matt Parsons.}
}
}
