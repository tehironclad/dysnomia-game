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


## Re-reads the endpoints from Config (after Settings → Apply).
func apply_config() -> void:
	rpc.endpoint = Config.rpc_url if Config.rpc_url != "" else Contracts.DEFAULT_RPC
	site.base_url = Config.site_api_base
	site.enabled = Config.site_api_enabled


func refresh_head() -> int:
	var r := await rpc.block_number()
	if r["ok"]:
		head_block = r["block"]
	return head_block
