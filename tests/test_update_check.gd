extends TestCase
## UpdateCheck: strict x.y.z versions, the manifest's shape, when the notice shows.


func test_parse_strict() -> void:
	eq(UpdateCheck.parse_version("1.2.3"), PackedInt32Array([1, 2, 3]))
	eq(UpdateCheck.parse_version("0.0.0"), PackedInt32Array([0, 0, 0]))
	eq(UpdateCheck.parse_version("10.20.300"), PackedInt32Array([10, 20, 300]))
	for bad in ["", "1", "1.2", "1.2.3.4", "v1.2.3", "1.2.3-beta", "1.2.3+b", " 1.2.3", "1.2.3 ", "1..3",
			"01.2.3", "1.02.3", "1.2.03", "1.a.3", "-1.2.3", "1.2.-3", "１.2.3", "1234567.0.0", "1.2.3\n", ".1.2"]:
		check(UpdateCheck.parse_version(bad).is_empty(), "accepted '%s'" % bad)
	for bad in [null, 1, 1.2, [], {}, PackedStringArray(["1", "2", "3"])]:
		check(not UpdateCheck.is_valid(bad), "accepted %s" % str(bad))


func test_compare() -> void:
	eq(UpdateCheck.compare("1.2.3", "1.2.3"), 0)
	eq(UpdateCheck.compare("1.2.4", "1.2.3"), 1)
	eq(UpdateCheck.compare("1.2.3", "1.10.0"), -1)  # numeric, not text
	eq(UpdateCheck.compare("2.0.0", "1.99.99"), 1)
	eq(UpdateCheck.compare("0.9.10", "0.9.9"), 1)


func test_manifest() -> void:
	eq(UpdateCheck.manifest_version({"status": "ok", "version": "0.9.1", "files": []}), "0.9.1")
	eq(UpdateCheck.manifest_version({"status": "not_configured"}), "")
	eq(UpdateCheck.manifest_version({"status": "unavailable", "version": "9.9.9"}), "")
	eq(UpdateCheck.manifest_version({"version": "9.9.9"}), "")  # no status
	eq(UpdateCheck.manifest_version({"status": "OK", "version": "9.9.9"}), "")
	eq(UpdateCheck.manifest_version({"status": "ok", "version": "9.9"}), "")
	eq(UpdateCheck.manifest_version({"status": "ok", "version": 9}), "")
	eq(UpdateCheck.manifest_version({"status": "ok"}), "")
	eq(UpdateCheck.manifest_version({"status": true, "version": "9.9.9"}), "")
	eq(UpdateCheck.manifest_version([]), "")
	eq(UpdateCheck.manifest_version(null), "")
	eq(UpdateCheck.manifest_version("ok"), "")


func test_should_notify() -> void:
	check(UpdateCheck.should_notify("0.9.0", "0.9.1"))
	check(UpdateCheck.should_notify("0.9.9", "1.0.0"))
	check(not UpdateCheck.should_notify("0.9.1", "0.9.1"), "same version")
	check(not UpdateCheck.should_notify("0.9.2", "0.9.1"), "older remote")
	check(not UpdateCheck.should_notify("", "0.9.1"), "dev build (no version)")
	check(not UpdateCheck.should_notify("0.9.0", ""), "no remote")
	check(not UpdateCheck.should_notify("0.9.0", "0.9.1-rc1"), "malformed remote")
	check(not UpdateCheck.should_notify("0.9.0", "0.9.1", "0.9.1"), "dismissed")
	check(UpdateCheck.should_notify("0.9.0", "0.9.2", "0.9.1"), "a later release after a dismissal")


func test_constant_https_urls() -> void:
	eq(UpdateCheck.DOWNLOAD_PAGE, Contracts.DEFAULT_SITE_API + "/download")
	eq(UpdateCheck.MANIFEST_URL, Contracts.DEFAULT_SITE_API + "/api/download-manifest")
	check(UpdateCheck.DOWNLOAD_PAGE.begins_with("https://"))
	check(UpdateCheck.MAX_BYTES <= 64 * 1024)
	# Dev runs carry no version: no notice and no request
	if not ProjectSettings.has_setting("application/config/version"):
		eq(UpdateCheck.current_version(), "")
