#lang pollen

◊(define-meta title "Effective Rust canisters")
◊(define-meta keywords "rust, ic, canisters")
◊(define-meta summary "A compilation of useful patterns for developing IC canisters in Rust.")
◊(define-meta doc-publish-date "2021-10-25")
◊(define-meta doc-updated-date "2022-10-16")

◊section{
◊section-title["how-to-read"]{How to read this document}

◊p{
  This document is a compilation of useful patterns and typical pitfalls I observed in the Rust code running on the ◊a[#:href "https://internetcomputer.org/"]{Internet Computer} (IC).
  Take everything in this document with a grain of salt: solutions that worked well for my problems might be suboptimal for yours.
  Every piece of advice comes with explanations to help you form your judgment.
}

◊p{
  Some recommendations might change if I discover better patterns or if the state of the ecosystem improves.
  I will try to keep this document up to date.
}
}

◊section{
◊section-title["code-organization"]{Code organization}

◊subsection-title["canister-state"]{Canister state}

◊p{
  The standard IC canister organization forces developers to use a mutable global state.
  Rust intentionally makes using global mutable variables hard, giving you a few options for organizing your code.
  Which option is the best?
}

◊advice["use-threadlocal"]{Use ◊code{thread_local!} with ◊code{Cell}/◊code{RefCell} for state variables.}

◊p{
  This option is the safest.
  It will help you avoid memory corruption and issues with asynchrony.
}

◊source-code["good"]{
thread_local! {
    static NEXT_USER_ID: Cell<u64> = Cell::new(0);
    static ACTIVE_USERS: RefCell<UserMap> = RefCell::new(UserMap::new());
}
}

◊p{
  Let us look at other options you might find in the wild and see what is wrong with them.
}

◊ol-circled{
◊li{
◊source-code["bad"]{
let state = ic_cdk::storage::get_mut<MyState>;
}
◊p{
  The Rust CDK used to provide a ◊a[#:href "https://docs.rs/ic-cdk/0.3.2/ic_cdk/storage/index.html"]{storage} abstraction that allows you to ◊a[#:href "https://docs.rs/ic-cdk/0.3.2/ic_cdk/storage/fn.get_mut.html"]{get} a value indexed by a type.
  The interface lets you obtain multiple non-exclusive mutable references to the same object, breaking language guarantees.
  The CDK team ◊a[#:href "https://github.com/dfinity/cdk-rs/blob/c7aaaddaaf5e39c90a51035f87be68a0215c8c10/src/ic-cdk/CHANGELOG.md#changed-2"]{removed} the storage API in version 0.5.0.
}
}

◊li{
◊source-code["bad"]{
static mut STATE: Option<State> = None;
}
◊p{
  Plain old global variables.
  This approach forces you to write boilerplate code to access the global state and suffers from the same safety issues as legacy ◊code{storage} API.
}
}

◊li{
◊source-code["bad"]{
lazy_static! {
    static STATE: RwLock<MyState> = RwLock::new(MyState::new());
}
}

◊p{
  This approach is memory-safe, although I find it confusing.
  Canisters cannot run multiple threads, so it is not obvious what happens if you try to obtain a lock twice.
  A failure to obtain a lock makes your canister trap, not block, as you might expect on most platforms.
  This distinction means your program's meaning changes depending on the compilation target (◊code{wasm32-unknown-unknown} vs. native code).
  ◊a[#:href "#target-independent"]{We do not want that}.
}
}
}

◊p{
  Let us see how non-exclusive mutable references can lead to hard-to-track bugs.
}

◊source-code["bad"]{
#[update]
fn register_friend(uid: UserId, friend: User) -> Result<UserId, Error> {
    let mut_user_ref = storage::get_mut<Users>() ◊circled-ref[1]
                           .find_mut(uid)
                           .ok_or(Error::NotFound)?;

    let friend_id = storage::get_mut<Users>().add_user(&friend); ◊circled-ref[2]

    mut_user_ref.friends.insert(friend_id); ◊circled-ref[3]

    Ok(friend_id)
}
}

◊p{
  The example shows a function that uses the storage API, but plain old mutable globals cause the same issue.
}
◊ol-circled{
◊li{We get a mutable reference pointing into our data structure.}
◊li{
  We call a function that modifies the data structure.
  This call might have invalidated the reference we obtained in step ◊circled-ref[1].
  The reference could now be pointing to garbage or into the middle of another valid object.
}
◊li{
  We use the original mutable reference to modify the object, potentially corrupting the heap.
}
}

◊p{
  The real-life code might be more complicated.
  The undesired mutation might happen deep in the function call stack.
  The issue can stay undetected until your canister is in active use, storing (and corrupting) user data.
  If we used a ◊code{RefCell}, the code would panic before we shipped it.
}

◊p{
  It should now be clear ◊em{how} to declare global variables.
  Let us discuss ◊em{where} to put them.
}

◊advice["clear-state"]{Put all your globals in one basket.}

◊p{
  Consider making all the global variables private and placing them in a single file, the canister main file.
  This approach has a few benefits:
}

◊ul[#:class "arrows"]{
 ◊li{Testing becomes easier because most of your code does not touch the globals.}
 ◊li{
   You can see global state usage patterns at a glance.
   For example, you can quickly validate that the canister persists all the stable data across upgrades.
 }
}

◊p{Consider also adding comments clarifying which variables are stable, like in the following example:}

◊source-code["good"]{
thread_local! {
    /* ◊b{stable}   ◊circled-ref[1] */ static USERS: RefCell<Users> = ... ;
    /* ◊b{flexible} ◊circled-ref[2] */ static LAST_ACTIVE: Cell<UserId> = ...;
}
}

◊p{I borrowed ◊a[#:href "https://sdk.dfinity.org/docs/language-guide/upgrades.html#_declaring_stable_variables"]{Motoko terminology} here:}
◊ol-circled{
  ◊li{
    The system preserves ◊em{stable} variables across upgrades.
    For example, a user database should probably be stable.
  }
  ◊li{
    The system discards ◊em{flexible} variables on code upgrades.
    For example, you can make a cache flexible if it is not crucial for your canister.
  }
}

◊p{
  If you have tried to test canister code, you probably noticed that this part of the development workflow is not polished yet.
  A quick way to make your life easier is to piggyback on the existing Rust infrastructure.
  This trick is possible only if you can compile the same canister code to a native target and WebAssembly.
}

◊advice["target-independent"]{Make most of the canister code target-independent.}

◊p{
  It pays off to factor most of the canister code into loosely coupled modules and packages and to test them independently.
  Most of the code that depends on the System API should live in the main file.
}

◊p{
  You can also create thin abstractions for the System API and test your code with a fake but faithful implementation.
  For example, you could use the following trait to abstract the ◊a[#:href "https://sdk.dfinity.org/docs/interface-spec/index.html#system-api-stable-memory"]{Stable Memory API}
}
◊source-code["good"]{
pub trait Memory {
    fn size(&self) -> WasmPages;
    fn grow(&self, pages: WasmPages) -> WasmPages;
    fn read(&self, offset: u64, dst: &mut [u8]);
    fn write(&self, offset: u64, src: &[u8]);
}
}

◊subsection-title["async"]{Asynchrony}

◊p{
  If a canister traps or panics, the system rolls back the state of the canister to the latest working snapshot◊sidenote["sn-op"]{
  This system behavior is part of the ◊a[#:href "/posts/06-ic-orthogonal-persistence.html#actors"]{orthogonal persistence} feature.
}.
If a canister makes a call and then traps in the callback, the canister might never release the resources allocated for the call.
}

◊advice["panic-await"]{Avoid panics after ◊code{await}}

◊p{
  Let us start with an example.
}

◊source-code["bad"]{
#[update]
async fn update_avatar(user_id: UserId, ◊b{pic: ByteBuf} ◊circled-ref[1] ) {
    let key = store_async(user_id, &pic)
                  ◊b{.await}      ◊circled-ref[2]
                  ◊b{.unwrap()};  ◊circled-ref[3]
    USERS.with(|users| set_avatar_key(user_id, key));
}
}

◊ol-circled{
◊li{The method receives a byte buffer with an avatar picture.}
◊li{
  The method issues a call to the storage canister.
  The call allocates a future on the heap, capturing the byte buffer.
}
◊li{ 
  If the call fails, the canister panics.
  The system rolls back the canister state to the snapshot it created right before the callback invocation.
  From the canister's point of view, it still waits for the reply and keeps the future and the buffer on the heap.
}
}

◊p{
  Note that there is no memory corruption.
  The canister is still in a valid state but will not release the buffer memory until the next upgrade.
}
◊p{
  The System API provides the ◊a[#:href "https://sdk.dfinity.org/docs/interface-spec/index.html"]{◊code{ic0.call_on_cleanup}} function to address this issue.
  Rust CDK versions ◊a[#:href "https://github.com/dfinity/cdk-rs/blob/c7aaaddaaf5e39c90a51035f87be68a0215c8c10/src/ic-cdk/CHANGELOG.md#fixed-4"]{0.5.1} and higher take advantage of this mechanism and release resources across await boundaries.
  I still recommend using explicit error handling instead of panics whenever possible.
}

◊p{
  Another problem you might experience with asynchrony and miss in tests is a future that has exclusive access to a resource for a long time.
}

◊advice["dont-lock"]{Don't lock shared resources across await boundaries.}

◊source-code["bad"]{
#[update]
async fn refresh_profile_bad(user_id: UserId) {
   let users = ◊b{USERS_LOCK.write().unwrap()}; ◊circled-ref[1]
   if let Some(user) = users.find_mut(user_id) {
       if let Ok(profile) = async_get_profile(user_id)◊b{.await} { ◊circled-ref[2]
           user.profile = profile;
       }
   }
}

#[update]
fn add_user(user: User) {
    let users = ◊b{USERS_LOCK.write().unwrap()}; ◊circled-ref[3]
    // ...
}
}
◊ol-circled{
◊li{We obtain exclusive access to the ◊code{users} map and make an async call.}
◊li{The system commits the canister state after the call suspends. The user map stays locked.}
◊li{Other methods accessing the map will panic until the call started in step ◊circled-ref[2] completes.}
}

◊p{
  This issue becomes quite nasty when combined with panics.
  If you lock a resource and panic after the ◊code{await}, the resource might stay locked forever◊sidenote["sn-fixed-0.5.1"]{As noted in the previous section, Rust CDK version 0.5.1 addresses this issue.}.
}

◊p{
  We're now ready to appreciate another benefit of ◊a[#:href "#use-threadlocal"]{using ◊code{thread_local!} for global variables}.
  The code above wouldn't have compiled if we used ◊code{thread_local!}.
  You cannot ◊code{await} in closure accessing thread-local variables:
}

◊source-code["bad"]{
#[update]
async fn refresh_profile(user_id: UserId) {
    ◊b{USERS.with}(|users| {
        if let Some(user) = users.borrow_mut().find_mut(user_id) {
            if let Ok(profile) = async_get_profile(user_id)◊b{.await} {
                ◊b{// The closure is synchronous, cannot await ^^^}
                // ...
            }
        }
    });
}
}

◊p{
  The compiler nudges you to write a less elegant but correct version:
}

◊source-code["good"]{
#[update]
async fn refresh_profile(user_id: UserId) {
    if !USERS.with(|users| users.borrow().has_user(user_id)) {
        return;
    }
    if let Ok(profile) = async_get_profile(user_id).await {
        USERS.with(|users| {
            if let Ok(user) = users.borrow_mut().find_user(user_id) {
                user.profile = profile;
            }
        })
    }
}
}

◊subsection-title["canister-interfaces"]{Canister interfaces}

◊p{
  Many people enjoy the Motoko compiler's code-first approach: you write an actor with public functions, and the compiler automatically generates the corresponding Candid file.
  This feature is indispensable in the early stages of development.
}

◊p{
  Canister with clients should follow the reverse pattern: the Candid file should be the source of truth, not the canister implementation.
}

◊advice["candid-file"]{Make your .did file the source of truth.}

◊p{
  Your Candid file is the primary documentation source for people interacting with your canister (including your team members working on the front end).
  The interface should be stable, easy to find, and well-documented.
}

◊source-code["good"]{
type TransferError = variant {
  // The debit account didn't have enough funds
  // for completing the transaction.
  InsufficientFunds : Balance;
  // ...
};

type TransferResult =
  variant { Ok : BlockHeight; Err : TransferError; };

service {
  // Transfer funds between accounts.
  transfer : (TransferArgs) -> (TransferResult);
}
}

◊p{
  The Candid package provides tools to help you keep your implementation and the public interface in sync:
}

◊ol-circled{
◊li{
  Annotate your canister methods with the ◊a[#:href "https://docs.rs/candid/0.8.2/candid/attr.candid_method.html"]{◊code{candid_method}} macro.
}
◊li{
  Use the ◊a[#:href "https://docs.rs/candid/0.8.2/candid/macro.export_service.html"]{◊code{export_service}} macro to extract your canister's effective Candid interface.
}
◊li{
  Call the ◊a[#:href "https://docs.rs/candid/0.8.2/candid/utils/fn.service_compatible.html"]{◊code{service_compatible}} function to check whether the effective interface is a subtype of the interface from the .did file.
}
}

◊source-code["good"]{
use candid::candid_method;
use ic_cdk_macros::update;

#[update]
#[candid_method(update)] ◊circled-ref[1]
async fn transfer(arg: TransferArg) -> Result<Nat, TransferError> {
  // ...
}

#[test]
fn check_candid_interface() {
  use candid::utils::{service_compatible, CandidSource};
  use std::path::Path;

  candid::export_service!(); ◊circled-ref[2]
  let new_interface = __export_service();

  service_compatible( ◊circled-ref[3]
    CandidSource::Text(&new_interface),
    CandidSource::File(Path::new("interface.did")),
  ).unwrap();
}
}

◊advice["errors-variant"]{Use variant types to indicate error cases.}

◊p{
  Just as Rust error types simplify error handling, Candid variants can help your clients gracefully handle edge cases.
  Variant types are also the ◊a[#:href "https://sdk.dfinity.org/docs/language-guide/errors.html#_prefer_optionresult_over_exceptions_where_possible"]{preferred} way of reporting errors in Motoko.
}
◊source-code["good"]{
type CreateEntityResult = variant {
  Ok  : record { entity_id : EntityId; };
  Err : opt variant {
    EntityAlreadyExists : null;
    NoSpaceLeftInThisShard : null;
  }
};

service : {
  create_entity : (EntityParams) -> (CreateEntityResult);
}
}

◊p{
  Note that even if a service method returns a result type, it can still ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec/#reject-codes"]{reject} the call.
  There is not much benefit from adding error variants such as ◊code{InvalidArgument} or ◊code{Unauthorized}.
  There is no meaningful way to recover from such errors programmatically.
  In most cases, rejecting malformed, invalid, or unauthorized requests is the right thing to do.
}

◊p{
  So you followed the advice and represented your errors as a ◊code{variant}.
  How do you add more error constructors as your interface evolves?
}

◊advice["candid-variant-extensibility"]{Make your variant types extensible.}

◊p{
  Candid variant types are tricky to evolve in a backward-compatible manner.
  One approach is to make the variant field optional:
}

◊source-code["good"]{
type CreateEntityResult = variant {
  Ok : record { /* */ };
  Err : ◊b{opt} variant { /* * /}
};
}

◊p{
  If some clients of your canister use an outdated version of your interface, the Candid decoder could replace unknown constructors with a ◊code{null}.
  This approach has two main issues:
}
◊ul[#:class "arrows"]{
  ◊li{The Candid decoder does not yet implement this magic (see ◊a[#:href "https://github.com/dfinity/candid/issues/295"]{dfinity/candid#295}).}
  ◊li{Diagnosing a problem if all you see is ◊code{null} is daunting.}
}

◊p{
  An alternative is to make your error type immutable and rely on a loosely typed catch-all case (and documentation) for extensibility.
}

◊source-code["good"]{
type CreateEntityResult = variant {
  Ok : record { /* */ };
  Err : variant {
    EntityAlreadyExists : null;
    NoSpaceLeftInThisShard : null;
    // Currently defined errors
    // ========================
    // error_code = 401 : Unauthorized.
    // error_code = 429 : Too many requests.
    // error_code = 503 : Canister overloaded.
    Other : record { error_code : nat; error_message : text }
  }
};
}

◊p{
  If you follow this approach, your clients will see a nice textual description if they experience a newly introduced error.
  Unfortunately, programmatically handling generic errors is more cumbersome and error-prone than well-typed extensible variants.
}
}

◊section{
◊section-title["optimization"]{Optimization}
◊subsection-title["cycle-consumption"]{Reducing cycle consumption}
◊p{
  The first step towards an optimized system is profiling.
}

◊advice["instruction-counter"]{Measure the number of instructions your endpoints consume.}

◊p{
  The ◊a[#:href "https://docs.rs/ic-cdk/0.5.3/ic_cdk/api/fn.instruction_counter.html"]{◊code{instruction_counter}} API will tell you the number of ◊em{instructions} your code consumed since the last ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec/#entry-points"]{entry point}.
  Instructions are the internal currency of the IC runtime.
  One IC instruction is the ◊a[#:href "https://en.wikipedia.org/wiki/Quantum"]{quantum} of work that the system can do, such as loading a 32-bit integer from a memory address.
  The system assigns an instruction cost equivalent to each ◊a[#:href "https://sourcegraph.com/github.com/dfinity/ic@cfdbbf5fb5fdbc8f483dfd3a5f7f627b752d3156/-/blob/rs/embedders/src/wasm_utils/instrumentation.rs?L155-177"]{WebAssembly instruction} and ◊a[#:href "https://sourcegraph.com/github.com/dfinity/ic@cfdbbf5/-/blob/rs/embedders/src/wasmtime_embedder/system_api_complexity.rs?L40-107"]{system call}.
  It also defines all its limits in terms of instructions.
  As of July 2022, these limits are:
}
◊ul[#:class "arrows"]{
◊li{One message execution: ◊a[#:href "https://github.com/dfinity/ic/blob/7d3fb4ef01416241205818450156aabd21c24b34/rs/config/src/subnet_config.rs#L19"]{5 billion} instructions.}
◊li{One round◊sidenote["sn-round"]{Each block produced by consensus initiates a round of execution.}: ◊a[#:href "https://github.com/dfinity/ic/blob/7d3fb4ef01416241205818450156aabd21c24b34/rs/config/src/subnet_config.rs#L46"]{7 billion} instructions.}
◊li{Canister upgrade: ◊a[#:href "https://github.com/dfinity/ic/blob/7d3fb4ef01416241205818450156aabd21c24b34/rs/config/src/subnet_config.rs#L56"]{200 billion} instructions.}
}
◊p{
  Instructions are not cycles, but there is a ◊a[#:href "https://github.com/dfinity/ic/blob/c01d7d1b2e18490a2f70d2fdf5b6aceccab5860c/rs/cycles_account_manager/src/lib.rs#L730-L738"]{simple linear function} that converts instructions to cycles.
  As of July 2022, ten instructions are equivalent to four cycles on an ◊a[#:href "https://github.com/dfinity/ic/blob/7d3fb4ef01416241205818450156aabd21c24b34/rs/config/src/subnet_config.rs#L288-L289"]{application} subnet.
}
◊p{
  Note that the value that ◊code{performance_counter} returns has meaning only within a single execution.
  You should not compare values of the instruction counter measured across async boundaries.
}

◊source-code["bad"]{
#[update]
async fn transfer(from: Account, to: Account, amount: Nat) -> Result<TxId, Error> {
  let start = ic_cdk::api::instruction_counter();

  let tx = apply_transfer(from, to, amount)?;
  let tx_id = archive_transaction(tx).◊b{await}?;

  ◊em{// ◊b{BAD}: the await point above resets the instruction counter.}
  let end = ic_cdk::api::instruction_counter();
  record_measurement(end - start);

  Ok(tx_id)
}
}

◊advice["serde-bytes"]{Encode byte arrays using the ◊a[#:href "https://crates.io/crates/serde_bytes"]{◊code{serde_bytes}} package.}

◊p{
  ◊a[#:href "https://github.com/dfinity/candid"]{Candid} is the standard interface definition language on the IC.
  The Rust implementation of Candid relies on a popular ◊a[#:href "https://serde.rs/"]{serde} framework and inherits all of serde's quirks.
  One such quirk is the inefficient encoding of byte arrays (◊code{Vec<u8>} and ◊code{[u8]}) in most serialization formats.
  Due to Rust ◊a[#:href "https://rust-lang.github.io/rfcs/1210-impl-specialization.html"]{limitations}, serde cannot treat byte arrays specially and encodes each byte as a separate element in a generic array, increasing the number of instructions required to encode or decode the message (often by a factor of ten or more).
}
◊p{
  The ◊code{HttpResponse} from the canister http protocol is a good example.
}
◊source-code["bad"]{
#[derive(CandidType, Deserialize)]
struct HttpResponse {
    status_code: u16,
    headers: Vec<(String, String)>,
    ◊em{// ◊b{BAD}: inefficient}
    body: Vec<u8>,
}
}

◊p{
  The ◊code{body} field can be large; let us tell serde to encode this field more efficiently using the ◊a[#:href "https://serde.rs/field-attrs.html#with"]{◊code{with}} attribute.
}

◊source-code["good"]{
#[derive(CandidType, Deserialize)]
struct HttpResponse {
    status_code: u16,
    headers: Vec<(String, String)>,
    ◊em{// ◊b{OK}: encoded efficiently}
    #[serde(with = "serde_bytes")]
    body: Vec<u8>,
}
}

◊p{
  Alternatively, we can use the ◊a[#:href "https://docs.serde.rs/serde_bytes/struct.ByteBuf.html"]{◊code{ByteBuf}} type for this field.
}

◊source-code["good"]{
#[derive(CandidType, Deserialize)]
struct HttpResponse {
    status_code: u16,
    headers: Vec<(String, String)>,
    ◊em{// ◊b{OK}: also efficient}
    body: serde_bytes::ByteBuf,
}
}

◊p{I wrote a tiny canister to measure the savings.}

◊figure{
◊marginnote["mn-http-response-canister"]{
  A canister endpoint measuring the number of instructions required to encode an HTTP response.
  We have to use a ◊a[#:href "https://docs.rs/ic-cdk/latest/ic_cdk/api/call/struct.ManualReply.html"]{◊code{ManualReply}} to measure the encoding time.
}
◊source-code["rust"]{
#[query(manual_reply = true)]
fn http_response() -> ManualReply<HttpResponse> {
    let start = ic_cdk::api::instruction_counter();
    let reply = ManualReply::one(HttpResponse {
        status_code: 200,
        headers: vec![("Content-Length".to_string(), "1000000".to_string())],
        body: vec![0; 1_000_000],
    });
    let end = ic_cdk::api::instruction_counter();
    ic_cdk::api::print(format!("Consumed {} instructions", end - start));
    reply
}
}
}
◊p{
  The unoptimized version consumes 130 million instructions to encode one megabyte, and the version with ◊code{serde_bytes} needs only 12 million instructions.
}

◊p{
  In the case of the ◊a[#:href "https://github.com/dfinity/internet-identity/"]{Internet Identity} canister, this change alone reduced the instruction consumption in HTTP queries by ◊a[#:href "https://github.com/dfinity/internet-identity/pull/184"]{order of magnitude}.
  You should apply the same technique for all types deriving serde's ◊code{Serialize} and ◊code{Deserialize} traits, not just for types you encode as Candid.
  A ◊a[#:href "https://github.com/dfinity/ic/commit/1b98a5d984176b1c948d0cb92227d88ad5ee8044"]{similar change} boosted the ICP ledger archive upgrades (the canister uses ◊a[#:href "https://cbor.io"]{CBOR} for state serialization).
}

◊advice["avoid-copies"]{Avoid copying large values.}

◊p{
  Experience shows that canisters spend a lot of their instructions copying bytes◊sidenote["sn-bulk-ops"]{
    Spending a lot of time in ◊code{memcpy} and ◊code{memset} is a common trait of many WebAssembly programs.
    That observation led to the ◊a[#:href "https://github.com/WebAssembly/bulk-memory-operations/blob/dcaa1b6791401c29b67e8cd7929ec80949f1f849/proposals/bulk-memory-operations/Overview.md"]{bulk memory operations} proposal included in the ◊a[#:href "https://webassembly.github.io/spec/core/appendix/changes.html?highlight=proposals#bulk-memory-and-table-instructions"]{WebAssembly 2.0 release}.}.
  Reducing the number of unnecessary copies often affects cycle consumption.
}
◊p{
  Let us imagine that we work on a canister that serves a single dynamic asset.
}
◊source-code["rust"]{
thread_local!{
    static ASSET: RefCell<Vec<u8>> = RefCell::new(init_asset());
}

#[derive(CandidType, Deserialize)]
struct HttpResponse {
    status_code: u16,
    headers: Vec<(String, String)>,
    #[serde(with = "serde_bytes")]
    body: Vec<u8>,
}

#[query]
fn http_request(_request: HttpRequest) -> HttpResponse {
    ◊em{// ◊b{NOTE}: we are making a full copy of the asset.}
    let body = ASSET.with(|cell| cell.borrow().clone());

    HttpResponse {
        status_code: 200,
        headers: vec![("Content-Length".to_string(), body.len().to_string())],
        body
    }
}
}
◊p{
  The ◊code{http_request} endpoint makes a deep copy of the asset for every request.
  This copy is unnecessary because the CDK encodes the response into the reply buffer as soon as the endpoint returns.
  There is no need for the encoder to own the body.
  The current macro API makes it unnecessarily hard to eliminate copies: the type of reply must have ◊code{'static} lifetime.
  There are a few ways to work around this issue.
}
◊p{
  One solution is to wrap the asset body into a ◊a[#:href "https://doc.rust-lang.org/std/sync/struct.Arc.html"]{reference-counting smart pointer}.
}
◊figure{
◊marginnote["mn-rc-bytes"]{
  Using a reference-counting pointer for large values.
  Note that the type of the ◊code{ASSET} variable has to change: all copies of the data must be behind the smart pointer.
}
◊source-code["rust"]{
thread_local!{
    static ASSET: RefCell<RcBytes> = RefCell::new(init_asset());
}

struct RcBytes(Arc<serde_bytes::ByteBuf>);

impl CandidType for RcBytes { /* */ }
impl Deserialize for RcBytes { /* */ }

#[derive(CandidType, Deserialize)]
struct HttpResponse {
    status_code: u16,
    headers: Vec<(String, String)>,
    body: RcBytes,
}
}
}
◊p{
  With this approach, you can save on copies without changing the overall structure of your code.
  A ◊a[#:href "https://github.com/dfinity/certified-assets/commit/47804eb70f44d2e5c73da26f0009540330293eb2"]{similar change} cut instruction consumption in the certified assets canister by 30%.
}

◊p{
  Another solution is to enrich your types with lifetimes and use the ◊a[#:href "https://docs.rs/ic-cdk/latest/ic_cdk/api/call/struct.ManualReply.html"]{◊code{ManualReply}} API.
}
◊source-code["rust"]{
use std::borrow::Cow;
use serde_bytes::Bytes;

#[derive(CandidType, Deserialize)]
struct HttpResponse<'a> {
    status_code: u16,
    headers: Vec<(Cow<'a, str>, Cow<'a, str>)>,
    body: Cow<'a, serde_bytes::Bytes>,
}

#[query(manual_reply = true)]
fn http_response(_request: HttpRequest) -> ManualReply<HttpResponse<'static>> {
    ASSET.with(|asset| {
        let asset = &*asset.borrow();
        ic_cdk::api::call::reply((&HttpResponse {
            status_code: 200,
            headers: vec![(
                Cow::Borrowed("Content-Length"),
                Cow::Owned(asset.len().to_string()),
            )],
            body: Cow::Borrowed(Bytes::new(asset)),
        },));
    });
    ManualReply::empty()
}
}
◊p{
  This approach allows you to get rid of all the unnecessary copies, but it complicates the code significantly.
  You should prefer the reference-counting approach unless you have to work with data structures that already have explicit lifetimes (◊a[#:href "https://docs.rs/ic-certified-map/0.3.0/ic_certified_map/enum.HashTree.html"]{◊code{HashTree}} from the ◊a[#:href "https://crates.io/crates/ic-certified-map"]{◊code{ic-certified-map}} package is a good example).
}
◊p{
  I experimented with a one-megabyte asset and measured that the original code relying on a deep copy consumed 16 million instructions.
  At the same time, versions with reference counting and explicit lifetimes needed only 12 million instructions◊sidenote["sn-candid-copy"]{
    The 25% improvement shows that our code does little but copy bytes.
    The code did at least ◊em{three} copies: ◊circled-ref[1] from a ◊code{thread_local} to an ◊code{HttpResponse}, ◊circled-ref[2] from the ◊code{HttpResponse} to candid's ◊a[#:href "https://sourcegraph.com/github.com/dfinity/candid@8b742c9701640ca220c356c23c5f834d13150cc4/-/blob/rust/candid/src/ser.rs?L28"]{value buffer}, and ◊circled-ref[3] from candid's ◊a[#:href "https://sourcegraph.com/github.com/dfinity/candid@8b742c9701640ca220c356c23c5f834d13150cc4/-/blob/rust/candid/src/ser.rs?L61"]{value buffer} to the call's ◊a[#:href "https://sourcegraph.com/github.com/dfinity/cdk-rs@39cd49a3b2ca6736d7c3d3bf3605e567302825b7/-/blob/src/ic-cdk/src/api/call.rs?L481-500"]{argument buffer}.
    We removed ⅓ of copies and got ¼ improvement in instruction consumption.
    So only ¼ of our instructions contributed to work unrelated to copying the asset's byte array.
  }.
}

◊subsection-title["module-size"]{Reducing module size}

◊p{
  By default, ◊code{cargo} spits out huge WebAssembly modules.
  Even the tiny ◊a[#:href "https://github.com/dfinity/cdk-rs/tree/58d276340c2592aa9dcbc4a3e79ef4ac4fca023b/examples/counter/src/counter_rs"]{counter} canister compiles to a whopping 2.2MiB monster under the default cargo ◊code{release} profile.
  This section presents simple techniques for reducing canister sizes.
}

◊advice["compile-size"]{Compile canister modules with size and link-time optimizations.}
◊p{
  The code that the Rust compiler considers fast is not always the most compact code.
  We can ask the compiler to optimize our code for size with the ◊code{opt-level = 'z'} ◊a[#:href "https://doc.rust-lang.org/cargo/reference/profiles.html#opt-level"]{option}.
  Unfortunately, that option alone does not affect the counter canister module size.
}
◊p{
  ◊a[#:href "https://doc.rust-lang.org/cargo/reference/profiles.html#lto"]{Link-time optimization} is a more aggressive option that asks the compiler to apply optimizations across module boundaries.
  This optimization slows down the compilation but its ability to prune unnecessary code is crucial for obtaining compact canister modules.
  Adding ◊code{lto = true} to the build profile shrinks the counter canister module from 2.2MiB to 820KiB.
  Add the following section to the ◊code{Cargo.toml} file at the root of your Rust project to enable size optimizations:
}
◊source-code["good"]{
[profile.release]
lto = true
opt-level = 'z'
}

◊p{
  Another option you can play with is ◊a[#:href "https://doc.rust-lang.org/cargo/reference/profiles.html#codegen-units"]{◊code{codegen-units}}.
  Decreasing this option reduces the parallelism in the code generation pipeline but enables the compiler to optimize even harder.
  Setting ◊code{codegen-units = 1} in the cargo release profile shrinks the counter module size from 820KiB to 777KiB.
}

◊advice["size-optimizer"]{Strip off unused custom sections.}

◊p{
  By default, the Rust compiler emits debugging information allowing tools to link back WebAssembly instructions to source-level constructs such as function names.
  This information spans several ◊a[#:href "https://webassembly.github.io/spec/core/binary/modules.html#custom-section"]{custom WebAssembly sections} that the Rust compiler attaches to the module.
  Currently, there is no use for debugging information on the IC. 
  You can safely remove unused sections using the ◊a[#:href "https://github.com/dfinity/ic-wasm"]{ic-wasm} tool.
}
◊source-code["shell"]{
$ cargo install ic-wasm
$ ic-wasm -o counter_optimized.wasm counter.wasm shrink
}
◊p{
  The ◊code{ic-admin shrink} step shrinks the counter canister size from 820KiB to 340KiB.
  ◊code{ic-wasm} is clever enough to preserve custom sections that the ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec/#state-tree-canister-information"]{IC understands}.
}

◊advice["twiggy"]{Use the ◊a[#:href "https://rustwasm.github.io/twiggy/"]{◊code{twiggy}} tool to find the source of code bloat.}

◊p{
  Some Rust language design choices (for example, ◊a[#:href "https://rustc-dev-guide.rust-lang.org/backend/monomorph.html"]{monomorphization}) trade execution speed for binary size.
  Sometimes changing the design of your code or switching a library can significantly reduce of the module size.
  As with any optimization process, you need a profiler to guide your experiments.
  The ◊a[#:href "https://rustwasm.github.io/twiggy/"]{◊code{twiggy}}◊sidenote["sn-twiggy-order"]{
    ◊code{twiggy} needs debug info to display function names.
    Run it ◊em{before} you shrink your module with ◊code{ic-wasm}.
  } tool is excellent for finding the largest functions in your WebAssembly modules.
}

◊figure{
◊marginnote["mn-counter-twiggy"]{
  Top contributors to the size of the WebAssembly module of the ◊a[#:href "https://github.com/dfinity/cdk-rs/tree/58d276340c2592aa9dcbc4a3e79ef4ac4fca023b/examples/counter/src/counter_rs"]{counter} canister.
  Custom sections with debugging information dominate the output, but we have to keep these sections to see function names in twiggy's output.
  Serde-based candid deserializer is the worst offender when it comes to code size.
}
◊source-code["shell"]{
  $ cargo install twiggy
  $ twiggy top -n 12 counter.wasm
 Shallow Bytes │ Shallow % │ Item
───────────────┼───────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────
        130610 ┊    16.42% ┊ custom section '.debug_str'
        101788 ┊    12.80% ┊ "function names" subsection
         75270 ┊     9.46% ┊ custom section '.debug_info'
         60862 ┊     7.65% ┊ custom section '.debug_line'
         52522 ┊     6.60% ┊ data[0]
         46581 ┊     5.86% ┊ custom section '.debug_pubnames'
         34800 ┊     4.38% ┊ custom section '.debug_ranges'
         15721 ┊     1.98% ┊ <&mut candid::de::Deserializer as serde::de::Deserializer>::deserialize_any::h6f19d3c43b6b4e95
         12878 ┊     1.62% ┊ <candid::binary_parser::ConsType as binread::BinRead>::read_options::hb957a7f286706947
         12546 ┊     1.58% ┊ candid::de::IDLDeserialize::new::h3afa758d80a71068
         11974 ┊     1.51% ┊ <&mut candid::de::Deserializer as serde::de::Deserializer>::deserialize_ignored_any::hb61449316ff3dae4
          9015 ┊     1.13% ┊ core::fmt::float::float_to_decimal_common_shortest::h1e6cfda96af3f1c0
        230729 ┊    29.01% ┊ ... and 1195 more.
        795296 ┊   100.00% ┊ Σ [1207 Total Rows]
}
}
◊p{
  Once you have identified the library that contributes to the code bloat the most, you can try to find a less bulky alternative.
  For example, I shrank the ICP ledger canister module by 600KiB by ◊a[#:href "https://github.com/dfinity/ic/commit/6f79736085f85dfd01493319816c9a3c9a563b73"]{switching} from ◊a[#:href "https://crates.io/crates/serde_cbor"]{◊code{serde_cbor}} to ◊a[#:href "https://crates.io/crates/ciborium"]{◊code{ciborium}} for ◊a[#:href "https://cbor.io"]{CBOR} deserialization.
}

◊advice["compress-modules"]{GZip-compress canister modules.}
◊p{
  The IC has the concept of a ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec/#ic-install_code"]{canister module}, the equivalent of an executable file in operating systems.
  Starting from ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec/#0_18_4"]{version 0.18.4} of the IC specification, canister modules can be not only binary-encoded WebAssembly files but also GZip-compressed WebAssembly files.
}
◊p{
  For typical WebAssembly files that do not embed compressed assets, GZip-compression can often cut the module size in half.
  Compressing the counter canister shrinks the module size from 340KiB to 115KiB (about 5% of the 2.2MiB module we started with!).
}
}

◊section{
◊section-title["infra"]{Infrastructure}

◊subsection-title["builds"]{Builds}

◊p{
  People using your canister might want to verify that it does what it claims to do (especially if the canister moves people's tokens around).
  The Internet Computer allows anyone to inspect the SHA256 hash sum of the canister WebAssembly module.
  However, there are no good tools yet to review the canister's source code.
  The developer is responsibile for providing a reproducible way of building a WebAssembly module from the published source code.
}

◊advice["reproducible-builds"]{Make canister builds reproducible.}

◊p{
  Getting a reproducible build by chance is about as likely as constructing a living organism by throwing random molecules together.
  At least two popular technologies can help you make your builds more reproducible: ◊a[#:href "https://linuxcontainers.org/"]{Linux containers} and ◊a[#:href "https://nixos.org/"]{Nix}.
  Containers are a more mainstream technology and are usually easier to set up, but Nix also has its share of fans.
  In my experience, Nix builds tend to be more reproducible.
  Use the technology with which you are most comfortable.
  It is the result that matters.
}

◊p{
  It also helps if you build your module using a public Continuous Integration system, making it easy to follow the module build steps and download the final artifact.
}
◊p{
  Finally, if your code is still evolving, make it easy for people to correlate module hashes with source code versions.
  You can mention the module hash in release notes, for example.
}
◊p{
  Read the ◊a[#:href "https://smartcontracts.org/docs/developers-guide/tutorials/reproducible-builds.html"]{Reproducible Canister Builds} article for more advice on reproducible builds.
}

◊subsection-title["upgrades"]{Upgrades}

◊p{Let me remind you how upgrades work:}
◊ol-circled{
◊li{The system calls the ◊code{pre_upgrade} hook if your canister defines it.}
◊li{
  The system discards canister memory and instantiates the new version of your module.
  The system preserves stable memory and makes it available to the next version.
}
◊li{
  The system calls the ◊code{post_upgrade} hook on the newly created instance if your canister defines it.
  The system does not execute the ◊code{init} function.
}
}

◊p{
  If the canister traps in any of the steps above, the system reverts the canister to the pre-upgrade state.
}

◊advice["plan-for-upgrades"]{Plan for upgrades from day one.}
◊p{
  You can live without upgrades during the initial development cycle, but even then losing state on each test deployment becomes annoying quickly.
  As soon as you deploy your canister to the mainnet, the only way to ship new code versions is to plan the upgrades carefully.
}

◊advice["version-stable-memory"]{Version your stable memory.}
◊p{
  You can view stable memory as a communication channel between your canister's old and new versions.
  All proper communication protocols have a version.
  One day, you might want to change the stable data layout or serialization format radically.
  The code becomes messy and brittle if the stable memory decoding procedure needs to ◊em{guess} the data format.
}
◊p{
  Save your nerve cells and think about versioning in advance.
  It is as easy as declaring, ◊quoted{the first byte of my stable memory is the version number}.
}

◊advice["test-upgrades"]{Always test your upgrade hooks.}
◊p{
  Testing upgrades is crucial.
  If they go wrong, you can lose your data irrevocably.
  Make sure that upgrade tests are an integral part of your infrastructure.
}
◊p{
  One approach to testing upgrades is to add an extra optional upgrade step before you execute the state validation part of your test.
  The following pseudo-code is in Rust, but the idea does not depend on the language.
}
◊source-code["good"]{
let canister_id = install_canister(WASM);
populate_data(canister_id);
◊b{if should_upgrade { upgrade_canister(canister_id, WASM); }}
let data = query_canister(canister_id);
assert_eq!(data, expected_value);
}
◊p{
  You then run your tests twice in different modes:
}
◊ol-circled{
◊li{In the ◊quoted{no upgrades} mode, your tests run without executing any upgrades.}
◊li{In the ◊quoted{upgrade} mode, your tests ◊quoted{self-upgrade} the canister before each assertion.}
}
◊p{
  This pattern can give you some confidence that canister upgrades preserve the state: the users cannot tell whether there was an upgrade or not.
  Testing that you can safely upgrade the canister from the previous version is also a good idea.
}

◊advice["upgrade-hook-panics"]{Do not trap in the ◊code{pre_upgrade} hook.}

◊p{
  The ◊code{pre_upgrade} and ◊code{post_upgrade} hooks appear to be symmetrical.
  The canister returns to the pre-upgrade state if either of these hooks traps.
  This symmetry is deceptive.
}

◊p{
  The hope is not lost if your ◊code{pre_upgrade} hook succeeds but the ◊code{post_upgrade} hook traps.
  You can figure out what went wrong and build another version of your canister that will not trap on upgrade.
  You might need to devise a complex multi-stage upgrade procedure, but at least there is a way out.
}

◊p{
  On the other hand, if your ◊code{pre_upgrade} hook traps, there is not much you can do about it.
  Changing canister behavior needs an upgrade, but that is what a broken ◊code{pre_upgrade} hook prevents you from doing.
}

◊p{
  The ◊code{pre_upgrade} hook will not let you down if you do not have one.
  The following advice will help you get rid of that hook.
}

◊advice["stable-memory-main"]{Consider using stable memory as your main storage.}
◊p{
  There is a cap on how many cycles a canister can burn during an upgrade.
  If your canister exceeds that limit, the system cancels the upgrade and reverts the canister state.
  If you serialize your whole state to stable memory in the ◊code{pre_upgrade} hook and the state grows large, you might not be able to upgrade your canister again.
}
◊p{
  One way of dealing with this issue is not to serialize the entire state in one go.
  You can use stable memory as your ◊quoted{disk store}, updating it incrementally with every update call.
  This way, you might not need the ◊code{pre_upgrade} hook, and your ◊code{post_upgrade} hook will burn few cycles.
}
◊p{
  There are a few downsides to this approach, however:
}
◊ul[#:class "arrows"]{
◊li{
  Organizing the flat address space of stable storage into a data structure is challenging, especially if your state consists of several interlinked data structures.
  The ◊a[#:href "https://github.com/dfinity/stable-structures"]{ic-stable-structures} and ◊a[#:href "https://github.com/seniorjoinu/ic-stable-memory"]{ic-stable-memory} packages attempt to alleviate the pain.
}
◊li{
  Changing the layout of your data might be infeasible.
  It will simply be too much work for a canister to complete the data migration in one go.
  Imagine writing a program that reformats an eight-gigabyte disk from FAT32 to NTFS without losing any data.
  By the way, that program must complete in under 5 seconds.
}
◊li{
  You must think carefully about the backward compatibility of your data structures.
  The latest version of your canister might have to read data that the version installed a few months ago wrote.
}
}
◊p{
  There is a tough trade-off between service scalability and code simplicity.
  If you plan to store gigabytes of state and upgrade the code, consider using stable memory as the primary storage.
}

◊subsection-title["observability"]{Observability}

◊p{
  At ◊a[#:href "https://dfinity.org/"]{dfinity}, we use metrics extensively and monitor all our production services.
  Metrics are indispensable for understanding the behaviors of a complex distributed system.
  Canisters are not unique in this regard.
}

◊advice["expose-metrics"]{Expose metrics from your canister.}

◊p{Let us look at two specific approaches you can take.}

◊ol-circled{
◊li{
◊p{
  The first approach is to expose a query call returning a data structure containing metrics.
  If you do not want to make the metrics public, you can reject queries based on the caller's principal.
  The main benefit of this approach is that the response is highly structured and easy to parse.
  I often use this approach in integration tests.
}

◊source-code["good"]{
pub struct MyMetrics {
  pub stable_memory_size: u32,
  pub allocated_bytes: u32,
  pub my_user_map_size: u64,
  pub last_upgraded_ts: u64,
}

#[query]
fn metrics() -> MyMetrics {
  check_acl();
  MyMetrics {
    // ...
  }
}
}
}
◊li{
◊p{
  The second approach is to expose the metrics in a format that your monitoring system can slurp through the canister HTTP gateway.
  For example, we use Prometheus for monitoring, so our canisters dump metrics in ◊a[#:href "https://prometheus.io/docs/instrumenting/exposition_formats/#text-based-format"]{Prometheus text-based exposition format}.
}

◊source-code["good"]{
fn http_request(req: HttpRequest) -> HttpResponse {
  match path(&req) {
    "/metrics" => HttpResponse {
        status_code: 200,
        body: format!(r#"◊b{stable_memory_bytes {}}
                         ◊b{allocated_bytes {}}
                         ◊b{registered_users_total {}}"#,
                      stable_memory_bytes, allocated_bytes, num_users),
        // ...
    }
  }
}
}

◊p{
  You do not have to link any heavy libraries, the format is brutally simple.
  The ◊code{format} macro will do if you need only simple counters and gauges.
  Histograms and labels require a bit more work, but you can get quite far with simple tools.
}
}
}

◊p{Some things you might want to keep an eye on:}
◊ul[#:class "arrows"]{
◊li{The size of stable memory.}
◊li{The size of the objects allocated on the heap (this size is relatively easy to get if you define a ◊a[#:href "https://doc.rust-lang.org/1.50.0/std/alloc/struct.System.html"]{custom allocator}).}
◊li{The lengths of internal data structures (queques, maps, etc.).}
◊li{The canister's cycle balance.}
◊li{The time of the last canister upgrade.}
}
}

◊section{
◊section-title["references"]{References}
◊p{
  The following are some of the heavily used Rust canisters for inspiration:
}
◊ul[#:class "arrows"]{
◊li{◊a[#:href "https://github.com/dfinity/internet-identity/tree/main/src/internet_identity"]{Internet Identity Backend} is an excellent example of a canister that uses ◊a[#:href "/posts/11-ii-stable-memory.html"]{stable memory as the primary storage}, obtains secure randomness from the system, and exposes Prometheus metrics.}
◊li{◊a[#:href "https://github.com/dfinity/sdk/tree/57006b55df0594a0f6925212048c09e6a7bc3397/src/canisters/frontend/ic-certified-assets"]{Certified Assets Canister} is an example of a canister that produces certified HTTP responses.}
}

◊section{
◊section-title["changelog"]{Changelog}
◊table{
  ◊tbody{
    ◊tr{
      ◊td{2022-10-16}
      ◊td{
        Another complete editorial pass. Mentioned a few CDK improvements.
      }
    }
    ◊tr{
      ◊td{2022-07-18}
      ◊td{Add a new section on ◊a[#:href "#optimization"]{canister optimization}.}
    }
    ◊tr{
      ◊td{2022-02-19}
      ◊td{Add notes on ◊a[#:href "#errors-variant"]{candid variant extensibility} and ◊a[#:href "#upgrade-hook-panics"]{panics in upgrade hooks}.}
    }
    ◊tr{
      ◊td{2021-10-25}
      ◊td{The first version.}
    }
  }
}
}
}
