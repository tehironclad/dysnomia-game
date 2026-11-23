class_name Contracts
extends RefCounted
## Single source of truth for Dysnomia contract addresses, function selectors,
## event topics and error selectors on PulseChain (chain 369).
##
## Facts and provenance: docs/LEARNINGS.md §2–3. Every address below had
## contract code on 2026-11-22; every selector is checked against
## tests/golden/selectors.json (keccak-256) by tests/test_contracts.gd.
##
## WORLD / WAR / GWAT / VITUS / H2O are NOT deployed. Their addresses live in
## WORLD_ADDRESSES and stay empty until verified on chain. Never guess them.

const CHAIN_ID := 369
const DEFAULT_RPC := "https://rpc.pulsechain.com"
const DEFAULT_SITE_API := "https://systm0.vercel.app"

const MOTZKIN_PRIME := 953467954114363

# --- Addresses (lower-case) ---------------------------------------------------
const VOID := "0x965b0d74591bf30327075a247c47dbf487dcff08"
const SIU := "0x43136735603d4060f226c279613a4dd97146937c"
const LAU_FACTORY := "0xba6ccd38992839aee20d5bf9125b1d94190b091c"
const CHO := "0xb6be11f0a788014c1f68c92f8d6ccc1abf78f2ab"  # also the Tethys token
const MAP := "0xd3a7a95012edd46ea115c693b74c5e524b3dda75"
const HECKE := "0x29a924d9b0233026b9844f2afeb202f1791d7593"
const CHAN := "0xe250bf9729076b14a8399794b61c72d0f4aefcd8"
const CHOA := "0x0f5a352fd4ca4850c2099c15b3600ff085b66197"
const SEI := "0x3dc54d46e030c42979f33c9992348a990acb6067"
const CHEON := "0x3d23084ca3f40465553797b5138cfc456e61fb5d"
const META := "0xe77bdae31b2219e032178d88504cc0170a5b9b97"
const RING := "0x1574c84ec7fa78fc6c749e1d242dbde163675e72"
const PANG := "0xee25ccd41671f3b67d660cf6532085586aec8457"
const ZI := "0xcbadd3c3957bd9d6c036863cb053feccf3d53338"
const XIE := "0x4df51741f2926525a21bf63e4769ba70633d2792"
const XIA := "0x7f4a4dd4a6f233d2d82be38b2f9fc0fef46f25fa"
const MAI := "0xc48b0a4e79ef302c8eb5be71f562d08fb8e6a3d8"
const QI := "0x4d9ce396be95dbc5f71808c38107eb7422fd9a03"
const AFFECTION := "0x24f0154c1dce548adf15da2098fdd8b8a3b8151d"
const FORNAX := "0xf6c50ffe7efbdee63a92e52a4d5e9aff7fb4a4d7"
const FOMALHAUTE := "0x7ae73c498a308247be73688c09c96b3fd06ddb84"  # also the Void chat log
const ERIS := "0xe843765114992e18061498aed708537ce9d924fa"
const TETHYS := CHO
const PHOBOS_QING := "0xb0ba7d36b7f0505879179ece7401f24eb653c6e1"  # "Zürich QING", token qZů
const PHOBOS_WAAT := "0x0116ffdf05f579f35879129076ff12f3c18bc4a0b85bda626f6bf7f2fcb7fafc"
const ZURICH_ASSET := "0x583d1c1427308f7f96bfd3e0d7a3f9674d8bf8ec"  # NOT the Phobos holding
const CROWS := "0x203e366a1821570b2f84ff5ae8b3bdeb48dc4fa1"
const WITHOUT := "0x173216ed67ebf3e6767d86e8b3ff32e0d64437bf"
const NONUKES_TOKEN := "0x174a0ad99c60c20d9b3d94c3095bc1fb9ddefd62"
const NONUKES_QING := "0x4dd0371c02631bfd17ad10ab7c0e35a047ff2d20"
const MATH := "0xb680f0cc810317933f234f67eb6a9e923407f05d"
const MULTICALL3 := "0xca11bde05977b3631167028862be2a173976ca11"
const WPLS := "0xa1077a294dde1b09bb078844df40758a5d0f9a27"
const DYSNOMIA_DEPLOYER := "0x0474606332105a1da6fc8ef7de2470551d389cb9"
## The deployer's nonce when WORLD was last confirmed absent. Movement past this
## is the WORLD launch signal (verify before trusting anything).
const DEPLOYER_NONCE_BASELINE := 712

## Latent layer: empty until verified on chain.
const WORLD_ADDRESSES := {"WORLD": "", "WAR": "", "GWAT": "", "VITUS": "", "H2O": ""}

const VOID_CHAT_FROM_BLOCK := 21000000
const MAP_FIRST_BLOCK := 22813947

# --- Function signatures → selectors ------------------------------------------
## Signature → 4-byte selector. Keys are canonical Solidity signatures.
const SELECTORS := {
	# writes
	"New(string,string)": "0x8c6dc5ec",  # LAUFactory
	"Username(string)": "0xc6bf2b65",  # LAU, owner only, ≤12 chars
	"Enter(address)": "0x37a2e752",  # CHO
	"Start(address,string,string)": "0x78519019",  # SEI
	"Play(address)": "0x74ff4718",  # CHOA
	"Su(address)": "0x753a0c09",  # CHEON
	"Chat(address,string)": "0xb340a780",  # CHOA.Chat(qing,msg) and QING.Chat(lau,msg)
	"Join(address)": "0x0764c80c",  # QING
	"Chat(string)": "0x21516fc4",  # LAU → Void
	"Beat(uint256)": "0xd5215e06",  # META, takes a Waat
	"approve(address,uint256)": "0x095ea7b3",
	"transfer(address,uint256)": "0xa9059cbb",
	"Alpha(uint64)": "0xe95b237f",
	"Beta(uint64)": "0x7ab0960d",
	"Pi()": "0x5c13dbf0",
	"Rho()": "0xa4566950",
	"Generate()": "0xd805b650",
	"Upsilon(uint64,bool)": "0xdf4c7406",
	"Leave()": "0xac8f5ead",
	"Void(bool,bool)": "0x414c3935",
	"Withdraw(address,uint256)": "0x884edad9",
	"Code(int256,int256,address)": "0x99790fb6",  # WORLD (latent)
	"Faa(address,uint256)": "0xe24893a2",  # WAR (latent)
	# reads
	"GetUserTokenAddress(address)": "0xe80c28bf",  # CHO: wallet → LAU
	"Yan(address)": "0x18025d89",  # CHAN: wallet → YUE
	"Username()": "0xc584460d",
	"Saat(uint256)": "0x088aee78",  # 0 = Pole, 1 = Soul, 2 = Aura
	"Bar(address)": "0xc253aded",  # YUE → (Hypobar, Epibar)
	"Waat()": "0xa138da0b",
	"Entropy()": "0x40c48dfa",
	"Asset()": "0xdf42e80e",
	"GWAT()": "0x8dd6363c",
	"CoverCharge()": "0xfbe5a232",
	"BouncerDivisor()": "0x0aae7978",
	"Admitted(address)": "0xdfffcc74",
	"Compliment(uint256)": "0x3353268d",  # HECKE → (int256 lon, int256 lat)
	"GetMapQing(int256,int256)": "0xb93ae85f",  # MAP(lat, lon): pass Compliment words swapped
	"GetQing(uint256)": "0x20bc1aa2",
	"Offset()": "0x5261d74a",
	"Cho()": "0x6872fc3c",
	"Yuan(address)": "0xd6047e37",  # needs from = wallet
	"Eta()": "0x4209b07c",  # RING, needs from = wallet
	"balanceOf(address)": "0x70a08231",
	"totalSupply()": "0x18160ddd",
	"decimals()": "0x313ce567",
	"name()": "0x06fdde03",
	"symbol()": "0x95d89b41",
	"allowance(address,address)": "0xdd62ed3e",
	"maxSupply()": "0xd5abeb01",  # whole tokens
	"owner(address)": "0x666e1b39",
	"aggregate3((address,bool,bytes)[])": "0x82ad56cb",
	"View()": "0x1686f265",  # AFFECTION; returns 48 words
	"Type()": "0xff762044",  # Dysnomia contracts name their class, e.g. "LAU"
	# WORLD family (latent): identify a deploy by its dispatcher's PUSH4 selectors.
	"Vitus()": "0xce29ab3c", "Water()": "0x6e69adcf", "Gwat(address,uint256)": "0x6912b95f",
	"War()": "0x94573097", "World()": "0x2d67bb91", "Cheon()": "0x51d95507", "Meta()": "0xd2717183",
	"Map()": "0xec557f40",
}

# --- Event topics ----------------------------------------------------------------
const TOPIC_ROOM_CHAT := "0xb916a3aaef1d0f80cd78f5fca0067f557f3db4a63748929d2e5e8d0014549374"  # LogEvent(string,uint64,uint64,string), per QING
const TOPIC_VOID_CHAT := "0x6b81130c485ac9b98332fa40c2e57900867815b0fe1497e1a168caf930fc9c9d"  # LogEvent(uint64,uint64,string), on FOMALHAUTE
const TOPIC_NEW_QING := "0x692bc76be0a4b0d71d90e36ee97b1f3c4141095ea3c22b01b9f620da2e4b5e2e"  # NewQing(address,address,uint256), on MAP
const TOPIC_TRANSFER := "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

const TOPICS := {
	"LogEvent(string,uint64,uint64,string)": TOPIC_ROOM_CHAT,
	"LogEvent(uint64,uint64,string)": TOPIC_VOID_CHAT,
	"NewQing(address,address,uint256)": TOPIC_NEW_QING,
	"Transfer(address,address,uint256)": TOPIC_TRANSFER,
}

# --- Errors: selector → [name, argument types] ----------------------------------
const ERRORS := {
	"0x08c379a0": ["Error", ["string"]],
	"0x4e487b71": ["Panic", ["uint256"]],
	"0x12efd467": ["NotStarted", ["address"]],
	"0x98aaa293": ["ZeroHoldings", ["address"]],
	"0x0efe67cb": ["OutOfRange", ["int256", "int256", "uint256"]],
	"0x647f6a38": ["UserNotEntered", ["address"]],
	"0xbba4853d": ["SoulNotEntered", ["uint64"]],
	"0xd466620a": ["NotAdmitted", ["uint64"]],
	"0xa59d7f4d": ["Forbidden", ["address"]],
	"0x694ecc8a": ["CoverChargeUnauthorized", ["address", "uint256"]],
	"0xac73eb51": ["PayCover", ["address", "uint256"]],
	"0x0be6bab5": ["OwnableUnauthorizedAccount", ["address", "address", "address"]],
	"0x3df42ef4": ["DysnomiaInsufficientBalance", ["address", "address", "address", "address", "address", "uint256", "uint256"]],
	"0x02e0f464": ["DysnomiaInsufficientAllowance", ["address", "address", "address", "address", "address", "uint256", "uint256"]],
}

## Plain-language explanations for reverts players will actually hit.
const ERROR_HINTS := {
	"NotStarted": "No YUE yet: call SEI.Start first.",
	"ZeroHoldings": "Your wallet holds 0 of its own YUE: CHOA.Play mints one.",
	"OutOfRange": "That cell is outside your range (Yeo) at this territory.",
	"UserNotEntered": "This wallet has no registered LAU (CHO.Enter).",
	"NotAdmitted": "Not admitted to this room: Join first.",
	"Forbidden": "This wallet holds WITHOUT and is banned here.",
	"Panic(0x12)": "Division by zero: one of the four holdings is missing (Fomalhaute and Fornax on your LAU, some Tethys, some qZů).",
	"Panic(0x1)": "Assertion failed (for example a WITHOUT holder on Join/Enter).",
}

const PANIC_CODES := {
	"1": "assert", "11": "arithmetic overflow", "12": "division by zero",
	"21": "enum conversion", "31": "pop on empty array", "32": "array index out of bounds",
}


static func selector(signature: String) -> String:
	assert(SELECTORS.has(signature), "Contracts: unknown signature %s" % signature)
	return SELECTORS[signature]


## Argument types parsed from a canonical signature, e.g. "Chat(address,string)"
## → ["address", "string"]. Handles one level of tuple nesting.
static func arg_types(signature: String) -> Array:
	var open := signature.find("(")
	var inner := signature.substr(open + 1, signature.length() - open - 2)
	return split_types(inner)


static func split_types(inner: String) -> Array:
	var out: Array = []
	if inner.is_empty():
		return out
	var depth := 0
	var cur := ""
	for ch in inner:
		if ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
		if ch == "," and depth == 0:
			out.append(cur)
			cur = ""
		else:
			cur += ch
	out.append(cur)
	return out


static func is_world_deployed() -> bool:
	return not String(WORLD_ADDRESSES["WORLD"]).is_empty()
