#lang pollen

◊(define-meta title "Tutorial: stable-structures")
◊(define-meta keywords "ic, rust")
◊(define-meta summary "An introduction into the stable-structures library.")
◊(define-meta doc-publish-date "2022-01-10")
◊(define-meta doc-updated-date "2022-01-10")


◊section{
◊section-title["introduction"]{Introduction}
◊p{
  Canisters hosted on the Internet Computer (IC) are mutable: a canisters's controller can upgrade the code to add new features or fix bugs without changing the canister's identity.
}
◊p{
  Since the ◊a[#:href "/posts/06-ic-orthogonal-persistence.html#upgrades"]{orthogonal persistence} feature cannot handle upgrades, the IC allows canisters to use an additional storage, called ◊em{stable memory}, to facilitate the data transfer between code versions.
  The ◊a[#:href "/posts/11-ii-stable-memory.html#conventional-memory-management"]{conventional approach} to canister state persistence is to serialize the entire state to stable memory in the ◊code{pre_upgrade} hook and decode it back in the ◊code{post_upgrade} hook.
  This approach is easy to implement and works well for relatively small datasets.
  Unfortunately, it does not scale well and can render a canister non-upgradable, so I ◊a[#:href "/posts/01-effective-rust-canisters.html#stable-memory-main"]{recommend} using stable memory as the main storage when possible.
}
◊p{
  The ◊a[#:href "https://github.com/dfinity/stable-structures"]{stable-structures} library aims to simplify managing data structures directly in stable memory.
  This article explains the philosophy behind the library and how to use it effectively.
}
}


◊section{
◊section-title["design-principles"]{Design principles}
◊p{
  Software designs reflect their creators' values.
  The following principles shaped the ◊code{stable-structures} library design.
}
◊ul[#:class "arrows"]{
  ◊li{
    ◊em[#:id "radical-simplicity"]{Radical simplicity.}
    Programming stable memory is significantly easier than working with conventional file systems.
    The IC solves many issues with which any respectable storage must deal: data integrity, partial writes, power outages, and atomicity of multiple writes.
    Even with all these issues sorted out, a complicated designs would be hard to implementation, debug, and maintain.
    Each data structure follows the simplest design that solves the problem at hand.
  }
  ◊li{
    ◊em[#:id "backward-compatibility"]{Backward compatibility.}
    Upgrading the library version must preserve the data.
    All data structures have a metadata section with the layout version.
    Newer implementations will respect old layouts and should not require data migration.
  }
  ◊li{
    ◊em{No ◊code{pre_upgrade} hooks.}
    A bug in the ◊code{pre_upgrade} hook can make your canister ◊a[#:href "/posts/01-effective-rust-canisters.html#upgrade-hook-panics"]{non-upgradable}.
    The best way to avoid this issue is not to have a ◊code{pre_upgrade} hook.
  }
  ◊li{
    ◊em{Limited blast radius.}
    If a single data structure has a bug, it should not corrupt the contents of other data structures.
  }
  ◊li{
    ◊em{No reallocation.}
    Moving large amounts of data is expensive and can lead to prohibitively high cycle consumption.
    All data structures must manage their memory without expensive moves.
  }
  ◊li{
    ◊em{Compatibility with ◊a[#:href "https://github.com/WebAssembly/multi-memory/blob/master/proposals/multi-memory/Overview.md"]{multi-memory} WebAssembly.}
    The design should work in the world when canisters have multiple stable memories since this feature is on the ◊a[#:href "https://forum.dfinity.org/t/proposal-wasm-native-stable-memory/15966#proposal-7"]{IC roadmap}.
  }
}
}


◊section{
◊section-title["abstractions"]{Abstractions}
◊subsection-title["memory"]{Memory}
◊p{
  The core abstraction of the library is the ◊a[#:href "https://docs.rs/ic-stable-structures/latest/ic_stable_structures/trait.Memory.html"]{◊code{Memory}} trait that models a WebAssembly ◊a[#:href "https://webassembly.github.io/multi-memory/core/exec/runtime.html#memory-instances"]{memory instance}◊sidenote["sn-multiple-memories"]{
    That design decision is not a coincidence.
    Eventually, canisters will have access to multiple memories, and each data structure will be able to reside in its own memory instance.
  }.
}
◊source-code["rust"]{
pub trait ◊b{Memory} {
    ◊em{/// Equivalent to WebAssembly memory.size.}
    fn ◊b{size}(&self) -> u64;

    ◊em{/// Equivalent to WebAssembly memory.grow.}
    fn ◊b{grow}(&self, pages: u64) -> i64;

    ◊em{/// Copies bytes from this memory to the heap (in Wasm, memory 0).}
    fn ◊b{read}(&self, offset: u64, dst: &mut [u8]);

    ◊em{/// Writes bytes from the heap (in Wasm, memory 0) to this memory.}
    fn ◊b{write}(&self, offset: u64, src: &[u8]);
}
}
◊figure[#:class "grayscale-diagram"]{
◊marginnote["mn-memory-trait"]{
  The ◊a[#:href "https://docs.rs/ic-stable-structures/latest/ic_stable_structures/trait.Memory.html"]{◊code{Memory}} trait models the WebAssembly ◊a[#:href "https://webassembly.github.io/multi-memory/core/exec/runtime.html#memory-instances"]{memory instance}.
  It allocates memory in 64KiB pages: the zero page spans addresses ◊code{0◊ndash{}ffff}, the first page◊mdash{}◊code{10000◊ndash{}1ffff}, etc.
}
◊(embed-svg "images/14-memory.svg")
}

◊p{
  Some important instances of the ◊code{Memory} trait are:
}
◊ul[#:class "arrows"]{
  ◊li{
    The ◊a[#:href "https://github.com/dfinity/stable-structures/blob/3d22d483b9c55b79f7b869e3cf930883687d9fda/src/ic0_memory.rs"]{◊code{Ic0StableMemory}} type delegates calls to the ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec#system-api-stable-memory"]{IC System API}.
  }
  ◊li{
    ◊a[#:href "https://github.com/dfinity/stable-structures/blob/3d22d483b9c55b79f7b869e3cf930883687d9fda/src/vec_mem.rs#L11"]{◊code{RefCell<Vec<u8>>}} implements the ◊code{Memory} interface for a byte array.
    This type is helpful for unit tests.
  }
  ◊li{
    The ◊a[#:href "https://docs.rs/ic-stable-structures/latest/ic_stable_structures/type.DefaultMemoryImpl.html"]{◊code{DefaultMemoryImpl}} type alias points to ◊code{Ic0StableMemory} when compiled to WebAssembly, otherwise it points to a memory backed by a byte array.
    This alias allows you to compile your canister to ◊a[#:href "/posts/01-effective-rust-canisters.html#target-independent"]{native code} with minimal effort.
  }
  ◊li{
    ◊a[#:href "https://docs.rs/ic-stable-structures/latest/ic_stable_structures/struct.RestrictedMemory.html"]{◊code{RestrictedMemory}} is a view of another memory restricted to a contiguous page range.
    You can use this type to split a large memory into non-intersecting regions if you know the size of the chunk in advance.
    ◊code{RestrictedMemory} works best for allocating relatively small fixed-size memories.
  }
}
◊figure[#:class "grayscale-diagram"]{
◊marginnote["mn-restricted-memory"]{
  Restricted memory limits the primary memory to a contiguous page range.
  The example on the diagram demonstrates splitting a 5-page primary memory into two memories: the first memory spans pages from zero to two (exclusive), the second memory spans pages from two to five (exclusive).
}
◊(embed-svg "images/14-restricted-memory.svg")
}
◊p{
  The most powerful and convenient way to create memories is to use the ◊a[#:href "https://docs.rs/ic-stable-structures/latest/ic_stable_structures/memory_manager/struct.MemoryManager.html"]{◊code{MemoryManager}}.
  This utility interleaves up to 255 non-intersecting memories in a single address space, acting similarly to a virtual memory subsystem in modern operating systems.
  The memory manager uses part of the parent memory to keep a dynamic translation table assigning page ranges to virtual memories.
}
◊figure[#:class "grayscale-diagram"]{
◊marginnote["mn-memory-manager"]{
  The memory manager interleaves multiple virtual memories in a single primary memory, using the first few pages to store metadata.
}
◊(embed-svg "images/14-memory-manager.svg")
}
◊p{
  Virtual memories can be represented non-contiguously, so a single write can translate to multiple system calls.
}

◊subsection-title["storable-types"]{Storable types}
◊p{
  The library does not impose any serialization format on you, and it does not provide a default.
  Depending on your needs, you might prefer ◊a[#:href "https://github.com/dfinity/candid"]{Candid}, ◊a[#:href "https://developers.google.com/protocol-buffers"]{Protocol Buffers}, ◊a[#:href "https://cbor.io/"]{CBOR}, ◊a[#:href "https://borsh.io/"]{Borsh}, ◊a[#:href "https://en.wikipedia.org/wiki/X.690#DER_encoding"]{DER}, or something else.
  The ◊code{Storable} trait abstracts data structures over your choice of serialization format.
}
◊figure{
◊marginnote["mn-storable-trait"]{
  The ◊code{Storable} trait abstracts data structures over your choice of serialization format.
}
◊source-code["rust"]{
pub trait ◊b[#:id "storable-trait"]{Storable} {
    ◊em{/// Serializes a value of a storable type into bytes.}
    fn ◊b{to_bytes}(&self) -> Cow<'_, [u8]>;

    ◊em{/// Deserializes a value of a storable type from a byte array.}
    ◊em{///}
    ◊em{/// ◊b{REQUIREMENT}: Self::from_bytes(self.to_bytes().to_vec()) == self}
    fn ◊b{from_bytes}(bytes: Vec<u8>) -> Self;
}
}
}
◊p{
  Some data structures, such as ◊a[#:href "stable-vector"]{stable vector}, need to know how much memory they need to allocate for each instance of your storable type.
  Such types rely on an extension of this trait providing this important metadata, ◊code{BoundedStorable}.
  ◊code{BoundedStorable} types are analogous in their function to ◊a[#:href "https://doc.rust-lang.org/std/marker/trait.Sized.html"]{◊code{Sized}} types, except that the compiler cannot deduce serialized sizes for you.
}
◊figure{
◊marginnote["mn-storable-trait"]{
  Some data structures require their values to implement ◊code{BoundedStorable} trait to know how much space they need to allocate for each item.
}
◊source-code["rust"]{
pub trait ◊b[#:id "bounded-storable-trait"]{BoundedStorable}: ◊a[#:href "#storable-trait"]{◊code{◊b{Storable}}} {
    ◊em{/// The maximum slice length that ◊b{to_bytes} can return.}
    ◊em{///}
    ◊em{/// ◊b{REQUIREMENT}: self.to_bytes().len() ≤ Self::MAX_SIZE as usize}
    const ◊b[#:id "max-size-attribute"]{MAX_SIZE}: u32;

    ◊em{/// Whether all values of this type have the same length (equal to Self::MAX_SIZE)}
    ◊em{/// when serialized. If you are unsure about this flag, set it to ◊b{false}.}
    ◊em{///}
    ◊em{/// ◊b{REQUIREMENT}: Self::IS_FIXED_SIZE ⇒ self.to_bytes().len() == Self::MAX_SIZE as usize}
    const ◊b[#:id "is-fixed-size-attribute"]{IS_FIXED_SIZE}: bool;
}
}
}
◊p{
  The library implements these traits for a few basic types, such as integers, allowing you to get away without any serialization libraries if you store only primitives.
}
}


◊section{
◊section-title["data-structures"]{Data structures}
◊p{
  The heart of the ◊code{stable-structures} library is a collection of data structures, each spanning one or more ◊a[#:href "#memory"]{memories}.
}
◊p{
  Stable structures do not compose◊sidenote["sn-nesting-restriction"]{
      The reason for this restriction is simplicity: most data structures are significantly easier to implement correctly and efficiently assuming they can span an entire ◊a[#:href "#memory"]{memory}.
  }: you cannot construct a stable map containing stable vectors as values, for example.
  Many conventional storage systems impose the same restriction.
  For example, SQL databases do not allow tables to hold other tables as values, and Redis does not allow nesting its ◊a[#:href "https://redis.io/docs/data-types/"]{data types}.
}
◊p{
  You can work around the restriction by using ◊a[#:href "https://en.wikipedia.org/wiki/Composite_key"]{composite keys} or defining several data structures linked with ◊a[#:href "https://en.wikipedia.org/wiki/Foreign_key"]{foreign keys}.
}
◊figure{
◊source-code["bad"]{
◊em{// ◊b{BAD}: stable structures do not support nesting.}
type BalanceMap = StableBTreeMap<Principal, StableBTreeMap<Subaccount, Tokens>>;
}
◊source-code["good"]{
◊em{// ◊b{GOOD}: use a composite key (a tuple) to avoid nesting.}
type BalanceMap = StableBTreeMap<(Principal, Subaccount), Tokens>;
}
◊source-code["bad"]{
◊em{// ◊b{BAD}: stable structures do not support nesting.}
type TxIndex = StableBTreeMap<Principal, StableVector<Transaction>>;
}
◊source-code["good"]{
◊em{// ◊b{GOOD}: use a composite key to avoid nesting.}
type TxIndex = StableBTreeMap<(Principal, TxId), Transaction>;
}
}

◊p{
  Let us examine the available data structures in detail.
}

◊subsection-title["stable-cell"]{Stable cell}
◊p{
  A ◊a[#:href "https://docs.rs/ic-stable-structures/latest/ic_stable_structures/cell/struct.Cell.html"]{Cell} represents a single value stored in stable memory in serialized form.
  Cell's contents in stable memory updates every time you change the underlying value.
}
◊figure{
◊marginnote["mn-log-interface"]{
  The core interface of the ◊code{Cell} stable structure.
}
◊source-code["rust"]{
impl<T: ◊a[#:href "#storable-trait"]{◊code{Storable}}, M: ◊a[#:href "#memory"]{◊code{Memory}}> struct ◊b{Cell}<T, M> {
    ◊em{/// Returns the current cell value.}
    ◊em{/// Complexity: O(1).}
    pub fn ◊b{get}(&self, idx: usize) -> Option<Vec<u8>>;

    ◊em{/// Updates the cell value.}
    ◊em{/// Complexity: O(value size).}
    pub fn ◊b{set}(&mut self, value: T) -> Result<T, ValueError>;
}
}
}
◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-cell-figure"]{
    A ◊code{Cell} persists a single value in stable memory and caches it on the heap.
    The serialized value and the value on the heap are always in sync.
  }
  ◊(embed-svg "images/14-cell.svg")
}
◊p{
  The primary use case for cells is storing canister configuration:
}
◊ul[#:class "arrows"]{
  ◊li{The ICRC-1 Ledger Archive canister persists its initialization arguments in a ◊a[#:href "https://github.com/dfinity/ic/blob/9cdb1e62bcd199f28ae0005ed3f762487a1454df/rs/rosetta-api/icrc1/archive/src/main.rs#L49"]{cell}.}
  ◊li{The Internet Identity Archive canister stores its init arguments in a ◊a[#:href "https://github.com/dfinity/internet-identity/blob/b66fe925fb0a337b09aaaa5beaf1a60994b19f14/src/archive/src/main.rs#L85"]{cell}.}
}

◊subsection-title["stable-vec"]{Stable vector}
◊p{
  A ◊code{Vec} is a growable mutable array similar to ◊a[#:href "https://doc.rust-lang.org/std/vec/struct.Vec.html"]{◊code{std::vec::Vec}}.
  Stable vector stores its items by value, so it must know how much space it needs to allocate for each item, hence the ◊a[#:href "#bounded-storable-trait"]{◊code{BoundedStorable}} bound on the item type.
}
◊p{
  Stable vector takes advantage of the ◊a[#:href "#is-fixed-size-attribute"]{◊code{T::IS_FIXED_SIZE}} attribute of the item type.
  If the value size is not fixed, the vector allocates a few extra bytes to store the actual entry size in addition to the ◊a[#:href "#max-size-attribute"]{◊code{T::MAX_SIZE}} bytes required for each value.
  If all the values have the same size, the vector implementation use ◊a[#:href "#max-size-attribute"]{◊code{T::MAX_SIZE}} for the item slot, saving up to 4 bytes per entry.
  This reduction is mostly helpful for vectors of primitives (e.g., ◊code{StableVec<u64>}).
}
◊figure{
◊marginnote["mn-log-interface"]{
  The core interface of the ◊code{Vec} stable structure.
}
◊source-code["rust"]{
impl<T: ◊a[#:href "#storable-types"]{◊code{BoundedStorable}}, Data: ◊a[#:href "#memory"]{◊code{Memory}}> struct ◊b{Vec}<T, Memory> {
    ◊em{/// Adds a new item at the vector's back.}
    ◊em{/// Complexity: O(T::MAX_SIZE).}
    pub fn ◊b{push}(&self, item: &T) -> Result<usize, GrowFailed>;

    ◊em{/// Removes an item from the vector's back.}
    ◊em{/// Complexity: O(T::MAX_SIZE).}
    pub fn ◊b{pop}(&self) -> Option<T>;

    ◊em{/// Returns the item at the specified index.}
    ◊em{/// Complexity: O(T::MAX_SIZE).}
    pub fn ◊b{get}(&self, index: usize) -> Option<T>;

    ◊em{/// Updates the item at the specified index.}
    ◊em{/// Complexity: O(T::MAX_SIZE).}
    pub fn ◊b{set}(&self, index: usize, item: &T);

    ◊em{/// Returns the number of items in the vector.}
    ◊em{/// Complexity: O(1).}
    pub fn ◊b{len}() -> usize;
}
}
}
◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-log-figure"]{
    A ◊code{Vec} is growable mutable array.
    The data representation depends on the ◊code{IS_FIXED_WIDTH} attribute of the item type.
    If the type's representation is not fixed-width, the vector implementation has to record the length of each entry.
  }
  ◊(embed-svg "images/14-vec.svg")
}
◊subsection-title["stable-log"]{Stable log}
◊p{
  A ◊a[#:href "https://docs.rs/ic-stable-structures/latest/ic_stable_structures/log/struct.Log.html"]{Log} is an append-only list of arbitrary-sized values, similar to ◊a[#:href "https://redis.io/docs/data-types/streams/"]{streams} in Redis.
  The log requires two memories: the ◊quoted{index} storing entry offsets and the ◊quoted{data} storing raw entry bytes.
  The number of instructions required to access old and append new entries does not depend on the number of items in the log, only on the entry size.
}
◊figure{
◊marginnote["mn-log-interface"]{
  The core interface of the ◊code{Log} stable structure.
}
◊source-code["rust"]{
impl<Index: ◊a[#:href "#memory"]{◊code{Memory}}, Data: ◊a[#:href "#memory"]{◊code{Memory}}> struct ◊b{Log}<Index, Data> {
    ◊em{/// Adds a new entry to the log.}
    ◊em{/// Complexity: O(entry size).}
    pub fn ◊b{append}(&self, bytes: &[u8]) -> Result<usize, WriteError>;

    ◊em{/// Returns the entry at the specified index.}
    ◊em{/// Complexity: O(entry size).}
    pub fn ◊b{get}(&self, idx: usize) -> Option<Vec<u8>>;

    ◊em{/// Returns the number of entries in the log.}
    ◊em{/// Complexity: O(1).}
    pub fn ◊b{len}() -> usize;
}
}
}
◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-log-figure"]{
    A ◊code{Log} is an append-only list of values.
    Logs needs two memories: the ◊quote{index} memory storing value offsets and the ◊quoted{data} memory storing raw entries.
    The image depics a log with two values: the first entry is 100 bytes long, the second entry is 200 bytes long.
  }
  ◊(embed-svg "images/14-log.svg")
}
◊p{
  Log is a versatile data structure that can be helpful in almost any application:
}
◊ul[#:class "arrows"]{
  ◊li{
    The ICRC-1 Ledger Archive canister stores archived transactions in a ◊a[#:href "https://github.com/dfinity/ic/blob/9cdb1e62bcd199f28ae0005ed3f762487a1454df/rs/rosetta-api/icrc1/archive/src/main.rs#L58"]{stable log}.
  }
  ◊li{
    The Internet Identity Archive canister stores anchor anchors in a ◊a[#:href "https://github.com/dfinity/internet-identity/blob/b66fe925fb0a337b09aaaa5beaf1a60994b19f14/src/archive/src/main.rs#L90"]{stable log}.
  }
  ◊li{
    The Chain-Key Bitcoin Minter canister persists all state modifications in a ◊a[#:href "https://github.com/dfinity/ic/blob/6cc83edf2cad91ca1bdbe8f7965060a9ef1d1960/rs/bitcoin/ckbtc/minter/src/storage.rs#L21"]{stable log}.
    Replaying events from the log is the minter's primary upgrade mechanism.
  }
}

◊subsection-title["stable-btree"]{Stable B-tree}
◊p{
  The ◊a[#:href "https://docs.rs/ic-stable-structures/latest/ic_stable_structures/btreemap/struct.BTreeMap.html"]{◊code{BTreeMap}} stable structure is an associative container that can hold any ◊a[#:href "#storable-types"]{bounded storable types}.
  The map needs to know sizes of the keys and values because it allocates nodes from a pool of fixed-size tree nodes◊sidenote["sn-"]{
    The ◊a[#:href "https://github.com/dfinity/stable-structures/blob/ed2fb6de50e56d2f93e67c2bfaa170fa4b1be60a/src/btreemap/allocator.rs#L13"]{tree allocator} the ◊a[#:href "https://en.wikipedia.org/wiki/Free_list"]{free list} allocator, which is the ◊a[#:href "#radical-simplicity"]{simplest allocator} capable of freeing memory.
  }.
}
◊figure{
◊marginnote["mn-log-interface"]{
  The core interface of the ◊code{BTreeMap} stable structure.
}
◊source-code["rust"]{
impl<K: ◊a[#:href "#bounded-storable-trait"]{◊code{BoundedStorable}}, V: ◊a[#:href "#bounded-storable-trait"]{◊code{BoundedStorable}}, M: ◊a[#:href "#memory"]{◊code{Memory}}> struct ◊b{BTreeMap}<K, V, M> {
    ◊em{/// Adds a new entry to the map.}
    ◊em{/// Complexity: O(log(N) * K::MAX_SIZE + V::MAX_SIZE).}
    pub fn ◊b{insert}(&self, key: K, value: V) -> Result<Option<V>, InsertError>;

    ◊em{/// Returns the value associated with the specified key.}
    ◊em{/// Complexity: O(log(N) * K::MAX_SIZE + V::MAX_SIZE).}
    pub fn ◊b{get}(&self, key: &K) -> Option<V>;

    ◊em{/// Removes an entry from the map.}
    ◊em{/// Complexity: O(log(N) * K::MAX_SIZE + V::MAX_SIZE).}
    pub fn ◊b{remove}(&self, key: &K) -> Option<V>;

    ◊em{/// Returns the number of entries in the map.}
    ◊em{/// Complexity: O(1).}
    pub fn ◊b{len}() -> usize;
}
}
}

◊p{
  If you need a ◊code{BTreeSet<K>}, you can use ◊code{BTreeMap<K, ()>} instead.
}
}


◊section{
◊section-title["tying-together"]{Tying it all together}
}

