extends Node
## Autoload "Chain": owns the RPC transport and the optional site accelerator.
## Game code reads the chain through state objects (Registry, Session…), which
## use Chain.rpc / Chain.multicall / Chain.logs. See docs/REWORK_PLAN.md §4.

var rpc: Rpc
var multicall: Multicall
var logs: LogScanner
var site: SiteApi

## Latest known head (updated by whoever reads it); -1 until known.
var head_block := -1


func _ready() -> void:
	rpc = Rpc.new()
	rpc.name = "Rpc"
	rpc.endpoint = Config.rpc_url if Config.rpc_url != "" else Contracts.DEFAULT_RPC
	add_child(rpc)
	multicall = Multicall.new(rpc)
	logs = LogScanner.new(rpc)
	site = SiteApi.new()
	site.name = "SiteApi"
	site.base_url = Config.site_api_base
	site.enabled = Config.site_api_enabled
	add_child(site)
	_verify_endpoint.call_deferred()


## What the RPC check found, for Settings/logs: "" until checked.
var rpc_note := ""


## A custom RPC (e.g. one saved by an older build in the shared settings file) that is
## not PulseChain, or does not answer, would make every read empty: no LAU, no bars,
## every territory "Wild". Verify eth_chainId once; fall back to the default node.
func _verify_endpoint() -> void:
	if rpc.endpoint == Contracts.DEFAULT_RPC:
		return
	var r := await rpc.request("eth_chainId", [])
	var cid := String(r.get("result", "")).hex_to_int() if r.get("ok", false) else -1
	if cid == Contracts.CHAIN_ID:
		rpc_note = "RPC %s is PulseChain (369)." % rpc.endpoint
		return
	rpc_note = "The saved RPC %s %s — using %s instead." % [rpc.endpoint,
		("is chain %d, not PulseChain" % cid) if cid >= 0 else "did not answer", Contracts.DEFAULT_RPC]
	push_warning("[Chain] " + rpc_note)
	print("[Chain] " + rpc_note)
	rpc.endpoint = Contracts.DEFAULT_RPC


## Re-reads the endpoints from Config (after Settings → Apply).
func apply_config() -> void:
	rpc.endpoint = Config.rpc_url if Config.rpc_url != "" else Contracts.DEFAULT_RPC
	_verify_endpoint()
	site.base_url = Config.site_api_base
	site.enabled = Config.site_api_enabled


func refresh_head() -> int:
	var r := await rpc.block_number()
	if r["ok"]:
		head_block = r["block"]
	return head_block
