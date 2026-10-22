extends "res://tests/test_case.gd"
## 擁有者截圖：華山拜師確認窗寫「basic_inner 5 級以上；basic_literacy 5 級以上；完成指定任務」，
## 少林弟子看到「你目前不符合：尚未拜入任何門派」。

func test_join_text_uses_display_names() -> void:
	var t := SectUi.join_text("huashan")
	assert_false(t.contains("basic_"), t)
	assert_true(t.contains("基本內功 5 級以上"), t)
	assert_true(t.contains("讀書識字 5 級以上"), t)
	assert_true(t.contains("完成任務「岳不群的考驗」"), t)

func test_no_internal_ids_in_any_sect_join_text() -> void:
	var re := RegEx.create_from_string("[a-z]+_[a-z_0-9]+")
	for sid in UiClient.table("sects"):
		var t := SectUi.join_text(str(sid))
		assert_true(re.search(t) == null, "%s: %s" % [sid, t])

func test_already_in_a_sect_says_which() -> void:
	var u := SectUi.unmet_conditions("huashan", { "sect": "shaolin", "gender": "M", "morality": 0, "pk": 0 })
	assert_true(u.has("你已經是少林弟子"), str(u))
	assert_false(u.has("尚未拜入任何門派"), str(u))
