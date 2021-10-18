#lang pollen

◊(define-meta title "Effective Rust canisters")
◊(define-meta doc-publish-date "2021-10-18")
◊(define-meta last-updated-date "2021-10-18")

◊section["how-to-read"]{How to read this document}

◊p{
  This document is a compilation of useful patterns and typical pitfalls I observed when developing Internet Computer canisters in Rust.
  Don't treat them as dogmas.
  Solutions that worked well for my problems might be suboptimal for yours.
  Every advice comes with explanations to help you make your own judgement.
}

◊p{
Some recommendation might change if I discover better patterns or if the state of the ecosystem improves.
I'll try to keep this document up to date.
}

◊section["code-organization"]{Code organization}

◊subsection["canister-state"]{Canister state}

◊p{
  The way canister are used on the IC platform requires them to use global mutable state.
  Rust, on the other hand, intentionally makes using global state a painful experience.
  Furthermore, there are more than one way to do it in Rust.
  Which option is the best?
}

◊advice["use-threadlocal"]{Use ◊code{thread_local!} with ◊code{Cell}/◊code{RefCell} for state variables.}

◊p{This is the safest option that will help you avoid memory corruption and issues with asynchrony.}

◊source-code["good"]{
thread_local! {
    static NEXT_USER_ID: Cell<u64> = Cell::new(0);
    static ACTIVE_USERS: RefCell<UserMap> = RefCell::new(UserMap::new());
}
}

◊p{Let's look at some other options you might find in the wild and see what's wrong with them.}

◊ol-circled{
◊li{
◊source-code["bad"]{
let state = ic_cdk::storage::get_mut<MyState>;
}
◊p{
  The Rust CDK provides the "storage" abstraction that allows one to get a mutable reference indexed by a type.
  In my opinion, introducing this abstraction wasn't a very good decision.
  This approach allows one to obtain multiple non-exclusive mutable references to the same object, which breaks language guarantees.
  You can easily shut yourself in a foot with this, I'll show you how in a minute.
}
}

◊li{
◊source-code["bad"]{
static mut STATE: Option<State> = None;
}
◊p{
  The plain old global variables.
  This approach forces you to write some boilerplate to access them and suffers from the same safety issues.
}
}

◊li{
◊source-code["bad"]{
lazy_static! {
    static STATE: RwLock<MyState> = RwLock::new(MyState::new());
}
}

◊p{
  This approach is memory-safe, but I find it very confusing.
  Threading is not available in canister, so it's not obvious what happens if one tries to obtain a lock for an already locked object.
  The meaning of your program changes depending on the compilation target.
}
}
}

◊p{
  Let's take a look how non-exclusive mutable references can lead to troubles.
  At first it might seem that if you don't have concurrency involved, there should be no harm.
  Unfortunately, that's not true.
  Let's look at an example.
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
  Here we have a function that uses the storage abstraction, but the mutable statics are essentially the same.
}
◊ol-circled{
◊li{We get a mutable reference pointing into our data structure.}
◊li{
  We call a function that modifies the data structure.
  This might have invalidated the reference we obtained in step ◊circled-ref[1], so now it could be pointing to garbage or into the middle of another valid object.
}
◊li{
  We use the original mutable reference to modify the object.
  This might lead to heap corruption.
}
}

◊p{
  Real code might be much more complicated, the mutation might happen in a function called from a function called from the canister method, etc.
  If we used a ◊code{RefCell}, we would get a panic before this code would be shipped (assuming enough test coverage).
}

◊p{
  It should be now clear ◊em{how} to declare global variables.
  Let's discuss ◊em{where} to put them.
}

◊advice["clear-state"]{Put all your globals in one basket.}

◊p{
  There are clear benefits in making all the global variables private and placing them in a single file, the canister main file:
}

◊ul[#:class "arrows"]{
 ◊li{Testing is easier because most of your code doesn't touch the globals directly.}
 ◊li{
   It's easier to understand how the global state is used.
   For example, checking that all the stable data is properly persisted across upgrades is trivial.
 }
}

◊p{Consider adding comments making it clear which variables are stable:}

◊source-code["good"]{
thread_local! {
    // Document which variables are ◊b{flexible} and which are ◊b{stable}.
    /* ◊b{stable}   ◊circled-ref[1] */ static USERS: RefCell<Users> = ... ;
    /* ◊b{flexible} ◊circled-ref[2] */ static LAST_ACTIVE: Cell<UserId> = ...;
}
}

◊p{
I borrowed ◊a[#:href "https://sdk.dfinity.org/docs/language-guide/upgrades.html#_declaring_stable_variables"]{Motoko terminology} here:
◊ol-circled{
  ◊li{
    ◊em{stable} variables are globals that are persisted across upgrades.
    For example, a user database should probably be stable.
  }
  ◊li{
    ◊em{flexible} variables are globals that don't survive an upgrade.
    For example, a cache might be flexible if persisting it across upgrades isn't critical for your product.
  }
}
}

◊p{
  If you ever tried to test canister code, you probably noticed that the UX is not quite polished yet.
  A quick way to make life easier is to piggy-back on the existing Rust infrastructure.
  For that we need the code to compile both to native and to WebAssembly.
}

◊advice["target-independent"]{Make most of the code target-independent.}

◊p{
  It pays off to factor most of the canister code into loosely coupled modules and packages and test them independently.
  Most of the code that depends on the system API should go into the main file.
}

◊p{
  It's also possible to create a thin abstractions for the System API and test your code with a fake but faithful implementations.
  For example, you can use the following trait to abstract the Stable Memory API:
}
◊source-code["good"]{
pub trait Memory {
    fn size(&self) -> WasmPages;
    fn grow(&self, pages: WasmPages) -> WasmPages;
    fn read(&self, offset: u32, dst: &mut [u8]);
    fn write(&self, offset: u32, src: &[u8]);
}
}

◊subsection["async"]{Asynchrony}

◊code{panics} and ◊code{traps} in canisters are somewhat special.
If your code traps or panics, the system rolls back the state of the canister to the latest working snapshot.
Unfortunately, this means that if your canister made a call and then panicked in the callback, it might never release the resources it allocated for the call.

◊advice["panic-await"]{Don't panic after ◊code{await}}

Let's look at an example.

◊source-code["bad"]{
#[update]
fn update_avatar(user_id: UserId, ◊b{pic: ByteBuf} ◊circled-ref[1] ) {
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
  The byte buffer is captured in a Rust future allocated on the heap.
}
◊li{ 
  If the call fails, the canister panics.
  The system rolls back the canister state to the snapshot created right before the callback invocation.
  From the canister point of view, it still waits for the reply and keeps the future and the buffer on the heap.
}
}

◊p{Note that there is no corruption, the canister is still in a valid state, but some resources, like memory, will never be released until the next upgrade.}
◊p{
  The system API was recently extended to deal with that problem (see ◊code{ic0.call_on_cleanup} in the ◊a[#:href "https://sdk.dfinity.org/docs/interface-spec/index.html"]{Internet Computer Interface Specification}).
  This issue is likely to be fixed in future versions of the Rust CDK.
}

◊p{Another problem that you might experience with asynchrony and miss in tests is a future that obtains exclusive access to a resource for a long period of time.}

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
◊li{We obtain exclusive access to the users map and makes an async call.}
◊li{The canister state is committed right after the call suspends. The user map stays locked.}
◊li{Other methods trying to access the map will panic until the code issued in step ◊circled-ref[2] completes.}
}

◊p{
  This issue becomes quite nasty when combined with panics: if you lock an important resource and then panic after await, the resource stays locked forever.
}

◊p{
  We're now ready to appreciate another benefit of ◊a[#:href "#use-threadlocal"]{using ◊code{thread_local!} for global variables}.
  The code above wouldn't have compiled if we used them.
  One simply can't await an async function from a closure accessing thread-local variables:
}

◊source-code["bad"]{
#[update]
async fn refresh_profile(user_id: UserId) {
    USERS.with(|users| {
        if let Some(user) = users.borrow_mut().find_mut(user_id) {
            if let Ok(profile) = async_get_profile(user_id).await {
                // The closure is synchronous, cannot await ^^^
                // ...
            }
        }
    });
}
}

The compiler nudges you to write the code correctly (though, admittedly, less elegantly):

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

◊subsection["canister-interfaces"]{Canister interfaces}

◊p{
  Many people enjoy the code-first approach supported by Motoko compiler: one writes an actor with some public functions, and the compiler automatically generates the corresponding Candid file.
  That's indeed a very useful feature, especially in the early stages of development.
}

◊p{
  I'll try to persuade you that for it should be the other way around for canisters that have clients: Candid file should be the source of truth, not the implementation.
}

◊advice["candid-file"]{Make your .did file the source of truth.}

◊p{
  Candid file is then main resource for people who want to interact with your canister (including your own team members who work on the frontend).
  It should provide a stable interface, be easy to read and navigate, have good names and plenty of API comments.
  Which is not something you can autogenerate.
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
  You might ask "how do I make sure that my .did file and my implementation are in sync"?
  And that's a very good question.
  The answer is "use the Candid tooling":
}

◊ul[#:class "arrows"]{
◊li{
  There are macros in the Rust CDK that allow you to annotate your Canister methods and extract the .did file.
}
◊li{
  The latest versions of the candid package have functions to check that one interface is a subtype of another interface, which is Candid way of saying "backward compatible".
}
}

◊advice["errors-variant"]{Use variant types to indicate error cases.}

◊p{
  Just as Rust error types make it easy for API consumers to recover from errors correctly, Candid variants can help your clients handle edge cases gracefully.
}
◊source-code["good"]{
type CreateEntityResult = variant {
  Ok  : record { entity_id : EntityId; };
  Err : variant {
    EntityAlreadyExists : null;
    NoSpaceLeftInThisShard : null;
  }
};

service : {
  create_entity : (EntityParams) -> (CreateEntityResult);
}
}

◊p{
  Note, however, that even if a service method returns a result type, it can still reject the call.
  There is probably not much benefit from adding error variants like ◊code{InvalidArgument} or ◊code{Unauthorized}.
  There is no meaningful way to recover from such errors programmatically.
  So rejecting malformed, invalid, or unauthorized requests is probably the right thing to do in most cases.
}

◊section["infra"]{Infrastructure}

◊subsection["builds"]{Builds}

◊p{
  Some people might want to verify that your canister does what it claims to do, especially if it moves tokens around.
  The Internet Computer allows anyone to inspect the SHA256 hash sum of the canister WebAssembly module.
  However, there are no good tools yet to inspect the source code from which that module was built.
  It's developer's responsibility to provide a reproducible way of building a WebAssembly module from the published sources.
}

◊advice["reproducible-builds"]{Make canister builds reproducible.}

◊p{
  Getting a reproducible build by chance is about as likely as constructing a living organism by throwing random molecules together.
  There are at least two popular technologies that can help you make your builds more reproducible: ◊a[#:href "https://linuxcontainers.org/"]{Linux containers} and ◊a[#:href "https://nixos.org/"]{Nix}.
  Containers are a more mainstream technology and are usually easier to setup, but Nix also has its share of fans.
  Use whatever technology you're comfortable with.
}

◊p{
  It's also helpful if your module is build by a public Continuous Integration system, so that it's easy to follow the steps that produced your module and download the artifact.
}
◊p{
  Finally, if your code is still evolving, make it easy for people to correlate module hashes with versions of the source code.
  For example, if you use GitHub releases, mention the module hash in the release notes.
}

◊subsection["upgrades"]{Upgrades}

◊p{A quick reminder on how the upgrades work:}
◊ol-circled{
◊li{The system calls ◊code{pre_upgrade} hook if your canister defines it.}
◊li{
  The system discards canister memory and instantiates the new version of your module.
  The system does preserve the stable memory, which is now available to the new version.
}
◊li{
  The system calls ◊code{post_upgrade} hook on the newly created instance if your canister defines it.
  The ◊code{init} function is not executed.
}
}

◊p{
  If the canister traps in any of the steps above, the system reverts the canister to the pre-upgrade state.
}

◊advice["plan-for-upgrades"]{Plan for upgrades from day one.}
◊p{
  You can live without upgrades during the initial development cycle, but even then loosing state on each deploy quickly becomes annoying.
  As soon as you deploy your canister to the Internet Computer, the only way to ship new versions of the code is to carefully plan the upgrades.
}

◊advice["version-stable-memory"]{Version your stable memory.}
◊p{
  You can view stable memory as a communication channel between the old and the new versions of your canister.
  All good communication protocols are versioned, and yours should be as well.
  For example, you might want to radically change stable data layout or serialization format in the future.
  If the stable memory decoding code needs to ◊em{guess} the data format, it tends to become quite messy and brittle.
  All you need is to think about versioning in advance.
  It's as easy as declaring "the first byte of my stable memory is version number".
}

◊advice["test-upgrades"]{Always test your upgrade hooks.}
◊p{
  Testing upgrades is very important, because if they go wrong, you lose your data irrevocably.
  Make sure that testing upgrades is an integral part of your infrastructure.
}
◊p{
  I'll describe one approach to testing upgrades that you can use in your integration tests.
  The idea is that you add an extra optional upgrade step before you execute the state validation part of your test.
  The pseudo-code below is in Rust, but integration tests written in shell will work just as well.
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
◊li{In "no upgrades" mode your tests run as usual, no upgrades are performed.}
◊li{In "upgrade" mode your tests "self-upgrade" the canister being tested to the same version that you're testing.}
}
◊p{
  This should give you some confidence that if you upgrade your canister, the state is preserved, and the users can't tell if there was an upgrade or not.
  Of course, it's also a good idea to test that your canister can be safely upgraded from the previous version.
}

◊advice["stable-memory-main"]{Consider using stable memory as your main storage.}
◊p{
  There is a cap on how many cycles a canister can burn during an upgrade.
  If your canister goes over that limit, the system cancels the upgrade and reverts the canister state.
  This means that if you serialize your whole state to stable memory in the ◊code{pre_upgrade} hook and your state grows huge, you might not be able to upgrade your canister ever again.
}
◊p{
  One way of dealing with this issue is avoiding the serialization step in the first place.
  You can use stable memory as your "disk store", this way you might not need the ◊code{pre_upgrade} hook at all, and your ◊code{post_upgrade} hook will need to burn few cycles.
}
◊p{
  There are quite a few downsides to this approach, however:
}
◊ul[#:class "arrows"]{
◊li{
  Organizing the flat address space of stable storage into a data structure is a challenge.
  This is especially true for complex states consisting of multiple interlinked data structures.
  As far as I know, there are no good libraries for that yet, but there are a few people working on addressing this.
}
◊li{
  Changing the layout of your data later on might be infeasible.
  It will simply be too much work for a canister to complete the data migration in one go.
  This might be as hard as writing a program that reformats an 8 gigabyte disk from FAT32 to NTFS without losing any data.
  By the way, that program must complete in under 5 seconds.
}
◊li{
  You need to think carefully about backward compatibility of your data structures.
  The latest version of your canister might need to be able to read data written by the version that you installed a few months ago.
}
}
◊p{
  Overall, it's a tough trade-off between scalability and code simplicity.
  If you plan to store gigabytes of state and upgrade the code, using stable memory as the main storage is a good option.
}

◊subsection["observability"]{Observability}

◊p{
  At DFINITY, we use metrics extensively and record a lot of data about our production services.
  This is indispensable when you're trying to understand behavior of a complex system.
  Canisters are not special in this regard.
}

◊advice["expose-metrics"]{Expose metrics from your canister.}

◊p{Let's look at two specific approaches you can take.}

◊ol-circled{
◊li{
◊p{
  The first approach is to expose a query call that returns a data structure with your metrics.
  If you don't want to expose this data to everybody for some reason, you can reject queries based on caller's principal.
  One of the main benefits of this approach is that the response is highly structured and easy to parse.
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
  The second approach is to expose the metrics in a format that your monitoring system can slurp directly through the canister HTTP gateway.
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
  As you can see, you don't have to link any fancy libraries, the format is very simple.
  If you only need simple counters and gauges, ◊code{format} macro will do.
  Histograms and labels require a bit more work, but you can get quite far with very simple tools.
}
}
}

◊p{Some things you might want to keep an eye on:}
◊ul[#:class "arrows"]{
◊li{The size of the stable memory.}
◊li{Size of the objects allocated on the heap (it's quite easy to get by defining a ◊a[#:href "https://doc.rust-lang.org/1.50.0/std/alloc/struct.System.html"]{custom allocator}).}
◊li{Sizes of internal data structures.}
◊li{Last time the canister was upgraded.}
}

◊section["references"]{References}
◊p{
  Below are a few examples of heavily used Rust canisters you might draw inspiration from.
  They aren't perfect, many of them made some choices that we now know weren't great.
}
◊ul[#:class "arrows"]{
◊li{◊a[#:href "https://github.com/dfinity/internet-identity/tree/main/src/internet_identity"]{Internet Identity Backend} is a good example of a canister that uses stable memory as the main storage, obtains secure randomness from the system, and exposes Prometheus metrics.}
◊li{◊a[#:href "https://github.com/dfinity/certified-assets"]{Certified Assets Canister} is a good example of a canister that produces certified HTTP responses.}
}
