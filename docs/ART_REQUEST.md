# 美術需求清單（給 ChatGPT 產圖用）

> 產好的圖一律放進 `K:\Project\JY-Mini OL\assets\art_in\`，檔名照下表。我會負責去背檢查、裁切、縮放、對齊格子，你不用處理。
> 缺圖不會壞：遊戲會用暫代圖頂著，有一張換一張。

---

## 0. 每次產圖都先貼這段「風格說明」

為了讓所有圖看起來是同一個遊戲，**每一張都先貼這段**，再接後面的個別描述：

```
Style: hand-painted 2D game art in the style of early-2000s Taiwanese wuxia
online RPGs. Ancient China setting. Soft painterly shading, warm muted
earth tones, clean readable silhouette, slight outline. Isometric game
camera (viewed from about 30 degrees above). No text, no UI, no watermark,
no frame.
```

角色和怪物另外加這段：

```
Single full-body character, transparent background (PNG with alpha).
Three-quarter view, body and face turned toward the LOWER-LEFT of the
image. Standing on the ground, feet at the bottom center. The character
fills about 80% of the image height. Square 1024x1024 image.
Nothing else in the image: no ground, no shadow, no scenery.
```

---

## 1. 戰鬥背景（6 張，必要）

規格：**1920×1080 PNG**。從斜上方約 30 度俯視，**畫面中央約 70% 要是平坦、空曠的地面**（遊戲會把 12×8 的菱形格子畫在上面），四周邊緣才放樹、石頭、牆等裝飾。不要有人物、動物、文字。

| 檔名 | 地區 | 描述（接在風格說明後面） |
|---|---|---|
| `bg_xixia_wild.png` | 西夏郊外 | Dry northwestern grassland at the edge of the desert, yellow-green tufts of grass, patches of sand and dirt, a few rocks, distant dunes and poplar trees at the edges. Bright afternoon light. |
| `bg_jingcheng_wild.png` | 京城南郊 | Green farmland outskirts south of an ancient Chinese capital, lush grass, a worn stone road crossing the ground, willow trees and a low earthen wall at the edges. Clear daylight. |
| `bg_dali_wild.png` | 大理郊外 | Lakeside meadow in Yunnan, soft green grass meeting a calm lake shore at one edge, blooming camellia bushes, misty mountains in the far background. |
| `bg_guiwang.png` | 鬼王洞 | Dark eerie cave interior, uneven stone floor, stalagmites and scattered bones at the edges, faint bluish-green ghostly light, a few candles on rocks. Center floor must stay open and walkable. |
| `bg_huashan.png` | 華山 | Narrow flat stone platform on a steep granite mountain, pine trees clinging to cliffs at the edges, sea of clouds below, sword-practice ground feel. |
| `bg_shaolin.png` | 少林寺 | Shaolin temple training courtyard, large flat grey stone slabs, wooden practice dummies and an incense burner at the edges, red temple walls and roof eaves along the back edge. |

---

## 2. 玩家角色（必要 4 張，選做 4 張）

每個角色**至少要 `idle`（站立）**。`attack`（出招）和 `hurt`（受傷）是選做，有的話戰鬥會更生動，沒有的話我用程式做晃動、前衝、閃紅。

| 檔名 | 角色 | 描述 |
|---|---|---|
| `unit_player_m_idle.png` | 男・布衣（未入派） | Young male wanderer, plain grey-brown cotton martial-arts clothes, cloth belt, hair tied in a topknot, holding a simple wooden sabre, ready stance. |
| `unit_player_f_idle.png` | 女・布衣（未入派） | Young female wanderer, plain light-blue cotton martial-arts clothes, hair in a simple bun with a ribbon, holding a wooden sabre, ready stance. |
| `unit_shaolin_m_idle.png` | 少林弟子（男限定） | Young Shaolin monk, shaved head with incense burn dots, orange-yellow monk robe with brown sash, bare-handed fist stance. |
| `unit_huashan_m_idle.png` | 華山弟子・男 | Young Huashan sect swordsman, dark blue-green long robe, white inner collar, hair tied up, holding a straight jian sword. |
| `unit_huashan_f_idle.png` | 華山弟子・女（選做） | Young Huashan sect swordswoman, dark blue-green robe, hair half-up, holding a straight jian sword. |
| `unit_player_m_attack.png` | 選做 | Same character as unit_player_m_idle, mid-attack, slashing forward toward the lower-left. |
| `unit_player_m_hurt.png` | 選做 | Same character, recoiling backward from a hit. |
| `unit_player_f_attack.png` / `_hurt.png` | 選做 | 同上，女版。 |

> 小技巧：先產 idle，滿意後在**同一個 ChatGPT 對話**裡說「same character, now attacking / now hurt」，人物比較不會走樣。

---

## 3. 怪物與敵人（8 張，必要）

| 檔名 | 名稱 | 描述 |
|---|---|---|
| `unit_m_rabbit_idle.png` | 野兔 | A grey-brown wild hare, alert, crouching. |
| `unit_m_bigrabbit_idle.png` | 大野兔 | A large, burly wild hare twice the normal size, darker fur, strong hind legs, aggressive. |
| `unit_m_wolf_idle.png` | 野狼 | A gaunt grey wolf with glowing green eyes, snarling, head low. |
| `unit_m_boar_idle.png` | 山豬 | A wild boar with dark bristly fur and curved tusks, charging stance. |
| `unit_m_bandit_idle.png` | 山賊 | Masked mountain bandit in ragged dark clothes, cloth mask over the lower face, holding a chipped single-edged dao sabre. |
| `unit_m_hs_trainee_idle.png` | 華山弟子（敵方切磋） | 可以不產，直接沿用 `unit_huashan_m_idle.png`。 |
| `unit_m_ghost_idle.png` | 鬼王洞小鬼 | A small ghostly imp, pale bluish-white skin, long black fingernails, tattered grey robe, floating slightly. |
| `unit_m_guiwang_idle.png` | 鬼王 | The Ghost King boss: tall menacing figure in a black and dark-purple robe, long wild white hair, pale face, ghostly purple aura around the hands. Larger and more imposing than normal enemies. |

怪物也可以加 `_attack` / `_hurt` 選做（例如 `unit_m_wolf_attack.png`）。

---

## 4. 選做：特效與小東西

沒有也沒關係，我會用程式畫。

| 檔名 | 用途 | 描述 |
|---|---|---|
| `fx_hit.png` | 打中 | Small burst of impact sparks, white-yellow, transparent background, 512x512. |
| `fx_slash.png` | 刀劍招式 | A curved white sword-slash arc, transparent background, 512x512. |
| `fx_palm.png` | 拳掌、內力招式 | A round shockwave of golden inner energy, transparent background, 512x512. |
| `tile_escape.png` | 逃跑格標記 | A glowing yellow isometric diamond-shaped floor marker (2:1 diamond), transparent background, 512x256. |

---

## 5. 第二批（2026-10-18 新增）

第一批 18 張已經全部用進遊戲了。世界改成 2001 原版地圖之後，多了 8 個新野外區域，現在這些區域借用舊背景。另外，NPC 對話框的立繪大多是剪影。下面照**優先順序**排列，做多少算多少，**缺的都有暫代圖，不會壞**。

> 放的位置和第一批一樣：`assets\art_in\`。放好跟我說一聲，新檔名要先登記到 `data/art.json`，我會順便處理。

### 5.1 新區域戰鬥背景（8 張，優先）

規格同第 1 節：1920×1080，斜上方約 30 度俯視，**中央約 70% 是平坦空地**，裝飾只放邊緣，不要人物、文字。每張前面一樣先貼第 0 節的風格說明。

| 檔名 | 地區 | 描述 |
|---|---|---|
| `bg_xixia_north.png` | 西夏北郊 | Cold windswept hillside north of a desert city, patchy snow over brown earth and dry grass, a dark cave mouth in a rocky cliff at one edge, grey overcast sky. |
| `bg_xixia_east.png` | 西夏東郊 | Rocky ground near an old mining area, wooden mine supports and ore carts at the edges, a small dark pond (black dragon pool) at one side, dusty yellow light. |
| `bg_xixia_south.png` | 西夏南坡 | Gentle southern slope with a shallow creek running along one edge, pebbles, reeds and tufts of grass, poplar trees, warm afternoon light. |
| `bg_desert_edge.png` | 大漠邊緣 | Edge of a great desert, hard-packed sand and scattered desert shrubs, sand dunes rising at the edges, a small oasis with palm-like trees and a spring at one corner, harsh bright sun. |
| `bg_river_road.png` | 河川古道 | Old dirt road along a wide river, the river and a stone bridge along one edge, willows and river stones, green banks, misty morning light. |
| `bg_hengshan_foot.png` | 恆山山麓 | Foot of a northern sacred mountain, flat ground between rice paddies and a riverbank, a roadside bamboo tea stall at one edge, mountains rising in the background. |
| `bg_huayin_road.png` | 華陰道 | Mountain road below steep granite peaks, flat packed earth, scattered pine trees and boulders at the edges, cliffs in the distance. |
| `bg_songshan_road.png` | 嵩山古道 | Ancient stone-paved pilgrim road through a pine forest toward a Buddhist mountain, old pines and stone lanterns at the edges, incense-like haze. |

### 5.2 華山女弟子（1 張）

| 檔名 | 角色 | 描述 |
|---|---|---|
| `unit_huashan_f_idle.png` | 華山弟子・女 | 第 2 節已列。女角拜入華山時目前借用男版圖。 |

### 5.3 NPC 立繪（對話框左邊，依優先順序）

原作的 NPC 對話框，左邊是**該 NPC 自己的全身立繪**。現在只有門派 NPC 借用門派服裝圖，其他人都是同一個剪影，框下寫「立繪待補」。

規格和戰鬥人物一樣（第 0 節兩段說明都要貼）：1024×1024、透明背景、全身、面向左下。檔名是 `unit_<NPC id>_idle.png`。

**第一優先（新手一定會遇到的）**

| 檔名 | 名稱 | 描述 |
|---|---|---|
| `unit_n_wujieshan_idle.png` | 武介山 | Worried middle-aged villager in a patched brown hunter's jacket, holding a bundle of rabbit pelts. |
| `unit_n_xx_innkeeper_idle.png` | 店小二 | Young inn waiter, towel over one shoulder, apron, cheerful and quick. |
| `unit_n_xx_station_idle.png` | 驛站管事 | Relay-station clerk in a dark official-style robe and hat, holding a register book and letters. |
| `unit_n_xx_wushi_idle.png` | 武館教頭 | Sturdy martial-arts hall instructor, muscular, short beard, sleeveless training vest, arms crossed. |
| `unit_n_xx_cha_idle.png` | 查小鏞 | Kindly old scholar with a long white beard, scholar's robe, holding a brush and a small notebook. 四個城門和山門的查小鏞共用這張。 |
| `unit_n_xx_guard_idle.png` | 西夏守衛 | City gate guard in lamellar armor and helmet, holding a long spear. 大理守衛可以共用。 |

**第二優先（商店、生活技能、任務）**

| 檔名 | 名稱 | 描述 |
|---|---|---|
| `unit_n_xx_pharmacist_idle.png` | 藥鋪掌櫃 | Elderly pharmacist with round spectacles, holding a small herb pouch. |
| `unit_n_xx_smith_idle.png` | 兵器鋪老闆 | Burly blacksmith with soot on his face, leather apron, holding a hammer. |
| `unit_n_xx_cook_idle.png` | 客棧廚子 | Plump inn cook in a white apron, holding a wok ladle. 大理廚子可以共用。 |
| `unit_n_xw_fisher_idle.png` | 漁夫 | Old fisherman with a conical bamboo hat and a fishing rod. |
| `unit_n_xw_woodcutter_idle.png` | 樵夫 | Sun-tanned woodcutter with an axe over his shoulder and a bundle of firewood. |
| `unit_n_taoyun_idle.png` | 陶耘 | Old farmer in straw hat and rolled-up trousers, holding a hoe. |
| `unit_n_dl_bukuai_idle.png` | 捕快 | Government constable in a red-and-black uniform, sabre at the waist. |
| `unit_n_dl_grocer_idle.png` | 雜貨鋪老闆 | Shrewd shopkeeper holding an abacus. |
| `unit_n_hf_teaman_idle.png` | 茶棚老闆 | Roadside tea-stall keeper holding a big copper teapot. 兩個茶棚老闆共用。 |
| `unit_n_de_host_idle.png` | 綠洲店家 | Desert innkeeper in a turban and loose robes. |
| `unit_n_xe_miner_idle.png` | 礦工阿火 | Old miner covered in coal dust, holding a pickaxe and a lantern. |
| `unit_n_sl_zhaiseng_idle.png` | 齋堂僧 | Chubby monk holding a rice bowl. |

**第三優先（金庸人物，劇情 NPC）**

| 檔名 | 名稱 | 描述 |
|---|---|---|
| `unit_n_yuebuqun_idle.png` | 岳不群 | Huashan sect master: refined middle-aged gentleman scholar-swordsman, neat beard, scholar's cap, sword at his side, polite smile. |
| `unit_n_zhangwuji_idle.png` | 張無忌 | Handsome gentle young man in plain clothes, kind expression. |
| `unit_n_weixiaobao_idle.png` | 韋小寶 | Cheeky teenage boy with a sly grin, fine but rumpled clothes. |
| `unit_n_shuanger_idle.png` | 雙兒 | Gentle, sweet young maiden in a simple dress. |
| `unit_n_chenjialuo_idle.png` | 陳家洛 | Elegant young noble scholar in white robes holding a folding fan. |
| `unit_n_yeerniang_idle.png` | 葉二娘 | Sinister woman with three blood-red scars on her cheek, dark robes, carrying a baby. |
| `unit_n_nanhai_idle.png` | 南海鱷神 | Brutish man with a huge head and tiny eyes, fierce expression, holding crocodile shears. |

（少林師父慧真、慧虛、慧空、知客僧，以及華山的梁發、陸大有，目前借用門派弟子的圖，看起來還可以，可以不產。）

### 5.4 選做：出招／受傷動作（讓戰鬥更生動）

沒有的話，我用程式做前衝、閃紅；有的話會直接換成動作圖。在**同一個對話**裡說「same character, now attacking / now hurt」，人物比較不會走樣。

`unit_player_m_attack.png`、`unit_player_m_hurt.png`、`unit_player_f_attack.png`、`unit_player_f_hurt.png`、`unit_shaolin_m_attack.png`、`unit_shaolin_m_hurt.png`、`unit_huashan_m_attack.png`、`unit_huashan_m_hurt.png`

### 5.5 之後才需要的（現在先不用產）

- **物品圖示**（武器、藥、兔皮、食物等 27 種）：遊戲還沒有放圖示的位置。我把介面做好之後，會再給你一份清單。
- **其他門派的服裝**：M3a 的 8 派已列在第 6 節；丐幫、明教、桃花島等 M3b 再補。

---

## 6. 第三批（2026-10-19 新增，M3a 八個新門派）

M3a 開放了武當、峨嵋、恆山、全真、古墓、靈鷲宮、星宿、血刀門 8 派，多了 16 個新地區、100 多個新 NPC 和 30 多種新怪。現在全部借用舊圖頂著（`data/art.json` 的 `alias`），**缺的都不會壞**。下面照**優先順序**排列，做多少算多少。

> 放的位置和前兩批一樣：`assets\art_in\`，檔名照下表。放好跟我說一聲，我把 `data/art.json` 裡那一條的 `alias` 換成正式圖。
> 每張一樣先貼第 0 節的風格說明；人物、怪物再加第 0 節第二段。

### 6.1 門派服裝（9 張，最優先）

玩家拜入門派後的戰鬥外觀。現在沒有圖的門派一律退回**布衣**（`player_m`／`player_f`），所以拜入新門派的玩家看起來跟未入派一樣。只列各派**允許的性別**（武當、全真、血刀只收男；峨嵋、恆山、古墓、靈鷲只收女；星宿男女都收）。

| 檔名 | 角色 | 描述 |
|---|---|---|
| `unit_wudang_m_idle.png` | 武當弟子・男 | Young Wudang Taoist swordsman, blue-grey Taoist robe, hair in a topknot with a wooden hairpin, straight jian sword on his back, white cloth leg wraps, calm composed expression, one hand in a tai-chi gesture. |
| `unit_emei_f_idle.png` | 峨嵋弟子・女 | Young Emei sect swordswoman (lay disciple), plain white nun-style robe with a teal sleeveless vest over it, hair in a bun with a wooden hairpin, straight sword at her waist, cool aloof expression. |
| `unit_hengshan_f_idle.png` | 恆山弟子・女 | Young Hengshan sect swordswoman, grey-white Buddhist robe, plain cloth head scarf, straight sword at her waist, gentle kind expression, ready stance. |
| `unit_quanzhen_m_idle.png` | 全真弟子・男 | Young Quanzhen Taoist swordsman, grey-blue Taoist robe, hair in a Taoist bun with a wooden hairpin, straight sword on his back, white leg wraps, solemn expression. |
| `unit_gumu_f_idle.png` | 古墓弟子・女 | Young Ancient Tomb sect swordswoman, flowing pure-white long dress, hair tied with a white silk ribbon, slender sword at her waist, cold detached expression, pale complexion. |
| `unit_lingjiu_f_idle.png` | 靈鷲宮弟子・女 | Young Lingjiu Palace disciple, pale green dress under a white fur-trimmed cape, hair in a bun with a wooden hairpin, bare-handed plum-blossom palm stance, cool snowy color palette. |
| `unit_xingxiu_m_idle.png` | 星宿弟子・男 | Young Xingxiu sect man, dark purple short jacket, poison pouches and a small clay jar at the belt, messy topknot, sly cunning grin, claw-hand stance. |
| `unit_xingxiu_f_idle.png` | 星宿弟子・女 | Young Xingxiu sect woman, dark purple dress, small clay jar and poison pouches hanging from the belt, cold sinister eyes, claw-hand stance. |
| `unit_xuedao_m_idle.png` | 血刀門弟子・男 | Young Blood Blade sect lama-warrior, dark red Tibetan-style lama robe, shaved head, curved blood-red sabre in hand, fierce expression. |

各派的切磋弟子（`m_<派>_dizi`）會直接沿用上表的圖，不用另外產。

### 6.2 新地區戰鬥背景（16 張）

規格同第 1 節：**1920×1080 PNG**，斜上方約 30 度俯視，**中央約 70% 是平坦空地**（遊戲會把 12×8 的菱形格子畫在上面），裝飾只放邊緣，不要人物、動物、文字。

**山門（8 張，優先）**

| 檔名 | 地區 | 描述 |
|---|---|---|
| `bg_wudang.png` | 武當派 | Flat stone courtyard of a Taoist temple complex on Wudang Mountain, green-tiled roofs and red walls along the back edge, stone steps, drifting clouds, pine and cypress trees at the edges. |
| `bg_emei.png` | 峨嵋派 | Blue-stone plaza of a Buddhist nunnery below the Golden Summit of Mount Emei, temple halls at the back edge, sea of clouds, ancient pines, quiet morning mist. |
| `bg_hengshan.png` | 恆山派 | Sword-practice terrace of a mountain nunnery halfway up a northern peak, grey-tiled hall at the back, a bronze incense burner with thin smoke, pines and mist at the edges. |
| `bg_quanzhen.png` | 全真教 | Stone courtyard of the Chongyang Taoist palace on Zhongnan Mountain, green-tiled halls built up the slope at the back, stone stairs, pines, cloud-wrapped peaks in the distance. |
| `bg_gumu.png` | 古墓派 | Inside an ancient stone tomb chamber, smooth bluish stone floor and walls, ever-burning oil lamps in wall niches, a stone table and stools at one edge, cold quiet atmosphere. Center floor open. |
| `bg_lingjiu.png` | 靈鷲宮 | Snow-swept stone plaza at the summit palace of the Tianshan mountains, carved stone gate in the clouds along the back edge, distant snow peaks, cold blue-white palette. |
| `bg_xingxiu.png` | 星宿派 | Muddy lakeshore of a remote grey-blue lake, wooden boardwalks and stilt houses at the back edge, small boats, a huge stone statue of a sea serpent at one corner, eerie overcast light. |
| `bg_xuedao.png` | 血刀門 | Snowy valley courtyard in front of a rock-cut cave temple, dark red door lintels, butter lamps, trampled snow training ground, a dark cave mouth at one edge. |

**野外與迷宮（8 張）**

| 檔名 | 地區 | 描述 |
|---|---|---|
| `bg_wudang_foot.png` | 武當山下 | Dense forest mountain road at the foot of Wudang, an old stone memorial archway at the back edge, fallen boulders pushed to the roadside, tall trees. |
| `bg_emei_road.png` | 峨嵋道 | Mountain path through bamboo groves toward Mount Emei, a small stream and stone steps at the edges, the misty mountain far behind. |
| `bg_emei_maze.png` | 峨嵋迷宮 | Dark dense forest where every tree looks the same, hanging vines and drifting fog at the edges, dim green light. Center floor open. |
| `bg_zhongnan_foot.png` | 終南山下 | Pine-forest mountain road at the foot of Zhongnan Mountain, a winding stream valley at one edge, peaks hidden in clouds. |
| `bg_gumu_maze.png` | 活死人墓迷宮 | Pitch-dark tomb passage, wet slimy stone walls, a massive fallen stone slab at one edge, an underground stream glinting along the side, bats hanging from the ceiling edge. Center floor open. |
| `bg_tianshan_road.png` | 天山道 | Snowfield at the foot of the Tianshan range, a packed-snow footpath, distant snow peaks, a hunter's log cabin with chimney smoke at one edge. |
| `bg_xingxiu_road.png` | 星宿海邊 | Sand dunes turning into mudflats, a narrow path marked with stuck-in snake bones, a grey-blue lake in the distance. |
| `bg_xuedao_road.png` | 大漠雪山道 | Western edge of the desert rising into snow mountains, gravel and sand slope, a snowy mountain path, a nomad felt tent at one edge. |

### 6.3 師父立繪（對話框左邊；收徒 NPC 與入門師父，12 張）

規格同 5.3：1024×1024、透明背景、全身、面向左下，第 0 節兩段說明都要貼。新玩家拜師、學第一套武功時一定會看到這幾位。

| 檔名 | 名稱 | 描述 |
|---|---|---|
| `unit_n_wd_zhangsanfeng_idle.png` | 張三丰（武當收徒） | Hundred-year-old Taoist grandmaster, snow-white hair and long beard, shabby grey cotton Taoist robe, sitting cross-legged, serene otherworldly aura, eyes half closed. |
| `unit_n_wd_yudaiyan_idle.png` | 俞岱巖（武當入門師父） | Middle-aged Taoist sitting in a rattan chair, a thin blanket over his crippled legs, sharp alert eyes, grey Taoist robe. |
| `unit_n_em_miejue_idle.png` | 滅絕師太（峨嵋收徒） | Stern middle-aged Buddhist nun, thin face, drooping eyebrows, cold severe expression, grey nun robe, holding a long straight sword. |
| `unit_n_em_jingjia_idle.png` | 靜迦師太（峨嵋入門師父） | Middle-aged Buddhist nun in a grey robe, one hand behind her back, the other pointing as if correcting a student, strict teacher look. |
| `unit_n_hg_dingxian_idle.png` | 定閒師太（恆山收徒） | Elderly Buddhist abbess with a shaved head, grey kasaya robe, holding prayer beads, kind calm expression. |
| `unit_n_hg_yihe_idle.png` | 儀和（恆山入門師父） | Young Buddhist nun with a shaved head, grey robe, holding a sword, frank straightforward expression. |
| `unit_n_qz_qiuchuji_idle.png` | 丘處機（全真收徒、入門師父） | Tall Taoist in his fifties, thick eyebrows and long black beard, apricot-yellow Taoist robe, sword at his waist, fiery righteous expression. |
| `unit_n_gm_zhangmen_idle.png` | 古墓派掌門人（收徒、入門師父） | Middle-aged woman in a flowing white robe, long loose black hair over her shoulders, cold dignified expression. |
| `unit_n_lj_tonglao_idle.png` | 天山童姥（靈鷲收徒、入門師父） | Ancient martial-arts matriarch with the body of an eight-year-old girl, white hair in a bun, deep purple brocade robe, hands clasped behind her back, shrewd imperious old eyes. Child-sized figure. |
| `unit_n_xh_dingchunqiu_idle.png` | 丁春秋（星宿收徒、入門師父） | Old man with a youthful rosy face and white crane-like hair, long white beard, purple robe, holding a feather fan, looks like an immortal but with a sinister smile. |
| `unit_n_xd_laozu_idle.png` | 血刀老祖（血刀收徒） | Gaunt old lama in a dark red robe, holding a curved blood-red sabre, cold malicious eyes. |
| `unit_n_xd_shengdi_idle.png` | 勝諦（血刀入門師父） | Lean muscular middle-aged lama in a red robe, curved sabre in hand, sharp fierce look. |

**第二優先（帶路、引薦、試煉）**

| 檔名 | 名稱 | 描述 |
|---|---|---|
| `unit_n_gm_sunpopo_idle.png` | 孫婆婆（古墓引路） | Hunched white-haired old servant woman in coarse cloth clothes, leaning on a wooden cane, kind face. |
| `unit_n_wd_yinjian_idle.png` | 引薦人（武當） | Middle-aged scholar in a long robe and square cap, holding a folding fan and a sealed letter. |
| `unit_n_sl_luohan_idle.png` | 羅漢練武師（少林十八銅人） | Bare-chested muscular Shaolin warrior monk, grey monk trousers, cloth belt, stern expression, arms crossed. |

（其他新 NPC 有的借門派服、有的借舊 NPC 圖，看起來還可以，可以不產。）

### 6.4 選做：新怪物與門派守衛

沒有也沒關係，現在借用野狼、山豬、山賊、守城官兵等舊圖。守衛是「敵對入山」時打玩家的強敵（新手打不贏）。

| 檔名 | 名稱 | 描述 |
|---|---|---|
| `unit_m_wd_guard_idle.png` | 武當護山弟子 | Burly Taoist guard in a dark robe, sword drawn, grim murderous look. |
| `unit_m_em_guard_idle.png` | 峨嵋護法師太 | Middle-aged nun warrior, sword raised, robe sleeves flying behind her. |
| `unit_m_hg_guard_idle.png` | 恆山護庵師太 | Middle-aged nun in a grey kasaya, long sword in a fighting stance, stern righteous look. |
| `unit_m_qz_guard_idle.png` | 全真執法道士 | Cold-faced middle-aged Taoist in an apricot-yellow robe, sword drawn. |
| `unit_m_gm_guard_idle.png` | 古墓守墓弟子 | Veiled woman in white holding a sword, deadly aura. |
| `unit_m_lj_guard_idle.png` | 靈鷲宮護衛 | Swordswoman in a white cape, frosty face mask, long sword drawn. |
| `unit_m_xh_guard_idle.png` | 星宿護法弟子 | Tall man in purple-black tight clothes wearing iron claws on both hands. |
| `unit_m_xd_guard_idle.png` | 血刀門護法 | Huge lama in a red robe holding a giant blood-red curved sabre with both hands, overwhelming presence. |
| `unit_m_sl_tongren_1_idle.png` | 十八銅人 | Bare-chested Shaolin monk whose whole body is coated in bronze powder, metallic bronze sheen. 三個陣次可以共用，我用色調區分。 |
| `unit_m_xh_snake_idle.png` | 毒蛇 | A brightly patterned venomous snake, coiled and flicking its tongue. |
| `unit_m_xh_scorpion_idle.png` | 毒蠍 | A palm-sized black scorpion with its stinger raised. |
| `unit_m_xh_toad_idle.png` | 毒蟾蜍 | A huge warty toad breathing out green poison mist. |
| `unit_m_lj_xuehu_idle.png` | 雪狐 | A snow-white fox with a bushy tail, crouching low on snow. |
| `unit_m_em_monkey_idle.png` | 獼猴 | A grinning macaque monkey clutching a steamed bun. |
| `unit_m_em_mz_snake_idle.png` | 竹葉青 | A bright green bamboo viper coiled on a bamboo stalk. |
| `unit_m_em_mz_ape_idle.png` | 白猿 | A tall white ape with long arms, about to pounce. |
| `unit_m_gm_bianfu_idle.png` | 墓穴蝙蝠 | A large tomb bat with dark brown wings spread, red eyes and sharp fangs. |
| `unit_m_gm_yufeng_idle.png` | 古墓玉蜂 | A fist-sized pale white jade bee with a glowing stinger. |
| `unit_m_gm_daomu_idle.png` | 盜墓賊 | Masked tomb robber in grey-black short clothes, a short knife in one hand and an iron shovel in the other. |
| `unit_m_gm_hongningbo_idle.png` | 洪凌波 | Young woman in an apricot-yellow Taoist robe holding a horsetail whisk, charming but vicious look. |
| `unit_m_wd_buyi_idle.png` | 不義之士 | Ragged scoundrel with a vicious glare, holding a single-edged sabre. |

### 6.5 之後才需要的（現在先不用產）

- **門派服裝的出招／受傷動作**（`unit_<派>_<性別>_attack.png`／`_hurt.png`）：idle 都到齊之後再說。
- **丐幫**的服裝與背景：已列在第五批（第 8 節，M3b）。**明教、桃花島**的服裝改到 M6／M7（拜入只存在於懷舊版；M3B_PLAN E7）。
- **新物品圖示**（暗器、解毒藥、皮鞭等）：同 5.5，等介面有圖示位置。

---

## 7. 第四批（2026-10-19 新增，故事包：2001 事件劇情與門派故事任務）

> **狀態（2026-10-20，M3c）**：已登記。47 個單位與 3 張背景（`yanmen`、`hengshan_s`、`hengshan_s_road`）已從借圖換成正式圖，蟲蛇 0.35–0.50、壯漢 1.05／1.10、其他 1.0（聯絡表：`K:\Project\JY-Mini-OL-Work\shots\m3c\WP-ART\m3c_art_contact*.png`）。

故事包開了**衡山、衡陽古道、雁門關**三個小地區，西夏城多了民房、衙門、皇宮門口與密道，還有 40 個左右的新 NPC 與 30 多種新怪。現在全部借用舊圖頂著（`data/art.json` 的 `alias`，右欄是目前借的圖），**缺的都不會壞**。下面照優先順序排列，做多少算多少。

> 放的位置和前幾批一樣：`assets\art_in\`，檔名照下表。放好跟我說一聲，我把 `data/art.json` 裡那一條的 `alias` 換成正式圖。
> 每張一樣先貼第 0 節的風格說明；人物、怪物再加第 0 節第二段。

### 7.1 新地區戰鬥背景（3 張，優先）

規格同第 1 節：**1920×1080 PNG**，斜上方約 30 度俯視，**中央約 70% 是平坦空地**，裝飾只放邊緣，不要人物、動物、文字。

| 檔名 | 地區 | 描述 | 目前借用 |
|---|---|---|---|
| `bg_hengshan_s_road.png` | 衡陽古道 | Yellow-earth ancient road winding between bamboo groves and terraced tea gardens, a wide river ferry landing with moored boats along the back edge, misty southern hills. | `wudang_foot` |
| `bg_hengshan_s.png` | 衡山 | Foot of the Southern Sacred Mountain Hengshan: a lotus pond with a narrow stone bridge to a willow islet at one edge, a small bamboo teahouse at the back edge, cloud-wrapped peaks behind. | `hengshan_foot` |
| `bg_yanmen.png` | 雁門關 | Great frontier pass of Yanmen: massive rammed-earth gate tower with banners along the back edge, a weathered wooden bridge over a dry riverbed at one corner, blowing yellow sand, harsh northern light. | `xixia_north` |

另外**皇宮門口**（`xx_palace`，西夏城內的房間）在城裡不會開戰，不需要背景；如果之後要做劇情插圖再說。

### 7.2 NPC 立繪（對話框左邊；39 張，任務給予者優先）

| 檔名 | 角色 | 描述 | 目前借用 |
|---|---|---|---|
| `unit_n_amb_etou_xe_idle.png` | 惡人頭子 | 金庸群俠傳OL 風格的野外惡人頭子立繪：滿臉橫肉、披著破舊皮襖、手提鬼頭刀，凶狠表情。 | `n_bandit_chief` |
| `unit_n_amb_etou_dlw_idle.png` | 惡人頭子 | 金庸群俠傳OL 風格的野外惡人頭子立繪：滿臉橫肉、披著破舊皮襖、手提鬼頭刀，凶狠表情。 | `n_bandit_chief` |
| `unit_n_amb_etou_ss_idle.png` | 惡人頭子 | 金庸群俠傳OL 風格的野外惡人頭子立繪：滿臉橫肉、披著破舊皮襖、手提鬼頭刀，凶狠表情。 | `n_bandit_chief` |
| `unit_n_hn_teaman_idle.png` | 茶店老闆 | 衡山小茶店老闆：圍著布裙、手提銅壺的中年漢子，笑容可掬。 | `n_hf_teaman` |
| `unit_n_dl_cunmin_idle.png` | 大理村民 | Sun-darkened Dali (Yunnan) villager in a blue-dyed cotton short jacket and head wrap, carrying a bamboo shoulder pole with two baskets of vegetables, curious gossipy expression; wuxia RPG unit sprite. | `n_taoyun` |
| `unit_n_dlw_guiyi_idle.png` | 詭異的人 | Mysterious Ming Cult (明教) branch leader in a flowing white robe with a red flame emblem embroidered on the chest, curved sabre at his hip, half-shadowed gaunt face with an eerie smile, standing in a dim desert cave; wuxia RPG unit sprite. | `m_bandit` |
| `unit_n_lf_lanfenghuang_idle.png` | 藍鳳凰 | 藍鳳凰，五毒教教主，二十來歲的苗家女子，赤足，藍色蠟染苗服繡滿花紋，耳垂與手腕戴粗大銀環，頭戴銀飾，笑容嫵媚，腰間掛小竹簍；2001 年金庸群俠傳 Online 斜 45 度 Q 版人物風格 | `huashan_f` |
| `unit_n_hs_lanyihan_idle.png` | 藍依涵 | 藍依涵，華山派年輕女弟子，青色勁裝，長髮束起，手持長劍收勢站立，神情溫和；2001 年金庸群俠傳 Online 斜 45 度 Q 版人物風格 | `huashan_f` |
| `unit_n_hn_liugongzi_idle.png` | 劉公子 | 劉公子：十七八歲的錦衣少年，月白長衫、腰繫玉帶，手捧一封大紅請帖，眉間帶著憂色。 | `n_wd_yinjian` |
| `unit_n_hn_dizi_idle.png` | 衡山弟子 | 衡山弟子：青灰色勁裝、腰懸長劍的年輕男弟子，抱拳迎客。 | `huashan_m` |
| `unit_n_hn_moda_idle.png` | 莫大先生 | 莫大先生：瘦削枯槁的老者，洗得發白的青布長衫，懷抱一把破舊胡琴，神情落寞。 | `n_xx_cha` |
| `unit_n_hn_lulianrong_idle.png` | 魯連榮 | 魯連榮（金眼雕）：身材魁梧的中年漢子，濃眉、一雙發黃的金眼，粗布短打，神情倨傲。 | `n_liangfa` |
| `unit_n_hn_mimike_idle.png` | 秘密客 | 秘密客：頭戴寬邊斗笠遮住半張臉的黑衣漢子，坐姿微傾，一手按著桌下的刀柄。 | `m_bandit` |
| `unit_n_xx_zhangbao_idle.png` | 張豹 | 張豹：滿臉通紅的西夏衙門差役，皂衣小帽、腰掛空酒葫蘆，醉眼惺忪（drunken yamen runner, red face, empty gourd at waist） | `n_xx_guard` |
| `unit_n_dl_wangbutou_idle.png` | 王捕頭 | 王捕頭：國字臉、絡腮鬍的老捕頭，紅纓官帽、佩刀，眼神凌厲（veteran constable, square face, full beard, saber） | `n_dl_bukuai` |
| `unit_n_xx_laodenuo_idle.png` | 勞德諾 | 勞德諾：鬚髮花白、神情老成的華山弟子，青衫佩劍，袖中藏信，眼神閃爍（grey-haired Huashan disciple, shifty, letter in sleeve） | `huashan_m` |
| `unit_n_hs_linghuchong_idle.png` | 令狐沖 | 令狐沖：瀟灑不羈的年輕劍客，青衫微敞、腰掛酒葫蘆，嘴角帶笑（carefree young swordsman with wine gourd） | `huashan_m` |
| `unit_n_hs_chengbuyou_idle.png` | 成不憂 | 成不憂：面容枯瘦、神情暴躁的老劍客，灰袍盤坐，劍橫膝上（gaunt irritable old swordsman, sword across knees） | `huashan_m` |
| `unit_n_ym_lingzhi_idle.png` | 靈芝商人 | 靈芝商人：風塵僕僕的中年行商，粗布短褂、背著空行囊，愁眉苦臉；同既有 NPC 立繪畫風（wuxia traveling herb merchant, dusty, worried） | `n_xx_pharmacist` |
| `unit_n_ym_qiangdao_idle.png` | 強盜 | 強盜：敞著衣襟、手提鬼頭刀的關外強盜，絡腮鬍，凶相（frontier bandit with ghost-head saber, open-collared robe） | `n_bandit_chief` |
| `unit_n_sl_daopin_idle.png` | 道品 | 中年少林僧人，灰色僧袍，手持念珠，面帶憂色，全身立繪 | `n_sl_zhike` |
| `unit_n_xx_xuzhu_idle.png` | 虛竹 | 年輕小和尚，濃眉大眼、鼻孔上翻、相貌樸拙憨厚，灰布舊僧袍，雙手合十、神情靦腆，全身立繪 | `n_sl_zhike` |
| `unit_n_xx_palace_guard_l_idle.png` | 皇宮左守衛 | 西夏皇宮侍衛，金漆鎧甲，手執長刀，面向右方，全身立繪 | `n_xx_guard` |
| `unit_n_xx_palace_guard_r_idle.png` | 皇宮右守衛 | 西夏皇宮侍衛，金漆鎧甲，手執長刀，面向左方，全身立繪 | `n_xx_guard` |
| `unit_n_xx_ada_idle.png` | 阿大 | 枯瘦老劍客，樸素長衫，懷抱長劍，目光銳利，全身立繪 | `n_xx_guard` |
| `unit_n_xx_yuner_idle.png` | 雲兒 | Young Song-dynasty commoner woman in a plain light-blue cotton jacket and skirt, hair in a simple bun with a cloth ribbon, holding a handkerchief, worried downcast expression; wuxia RPG unit sprite, same style as existing town NPCs. | `n_em_yingyueer` |
| `unit_n_xx_litaian_idle.png` | 李台安 | Neat young pharmacy apprentice in a grey scholar-style robe with sleeves tied back, holding a bronze herb grinder (藥碾), slightly proud posture; wuxia RPG unit sprite. | `n_xx_pharmacist`（第三輪審查：原本借店小二，端茶盤不合身分；老藥師年紀也不合，仍是暫代） |
| `unit_n_xx_abao_idle.png` | 礦工阿寶 | Sturdy sun-darkened young miner in a patched brown short jacket and straw sandals, carrying a woven basket of purple and green ore on his back, scratching his head with a confused honest grin; wuxia RPG unit sprite. | `n_xe_miner` |
| `unit_n_hn_longmen_idle.png` | 龍門遺孤 | 十五六歲的瘦削少年，粗布短打、肩搭抹布，眼神冷硬，衡山茶店打雜，水墨武俠立繪 | `n_xe_miner` |
| `unit_n_wd_yuanyin_idle.png` | 圓音 | 中年少林僧，灰布僧袍、手持念珠、神情沉鬱，水墨武俠立繪 | `n_sl_zhike` |
| `unit_n_wd_yuanye_idle.png` | 圓業 | 粗壯少林僧，灰布僧袍、濃眉怒目、脾氣火爆，水墨武俠立繪 | `n_sl_zhike` |
| `unit_n_wd_zhaomin_idle.png` | 趙敏 | 女扮男裝的蒙古郡主，白色公子袍、手搖摺扇、明豔狡黠，水墨武俠立繪 | `n_em_yingyueer` |
| `unit_n_ym_hufei_idle.png` | 胡斐 | 濃眉大眼、滿腮虯髯的豪俠，粗布勁裝、腰掛單刀，雁門關背景，水墨武俠立繪 | `n_chenjialuo` |
| `unit_n_xx_qiaofeng_idle.png` | 喬峰 | 身材魁偉的丐幫英雄，粗布衣衫、虎目方臉、手捧酒碗，水墨武俠立繪 | `n_chenjialuo` |
| `unit_n_xx_azi_idle.png` | 阿紫 | 紫衫少女，眉目如畫、嘴角帶著邪氣的笑，手裡玩著毒蟲，水墨武俠立繪 | `n_em_yingyueer` |
| `unit_n_dl_limochou_idle.png` | 李莫愁 | 杏黃道袍的美貌道姑，手持拂塵、眼神冷豔，赤練仙子，水墨武俠立繪 | `n_em_jixiaofu` |
| `unit_n_lj_baiyong_idle.png` | 白勇 | 皮膚黝黑的精壯海島漢子，短褂、腰纏包袱，水墨武俠立繪 | `n_xe_miner` |
| `unit_n_xd_pantu_idle.png` | 形跡可疑的僧人 | 裹著破皮襖的血刀門紅衣僧，背著包袱、手按刀柄、驚慌失措，雪原背景，水墨武俠立繪 | `n_xd_shanyong` |
| `unit_n_hg_lincai_idle.png` | 琳彩 | 圓臉小尼姑，灰色僧袍、膝上攤著縫了一半的僧袍、手指纏著布條，水墨武俠立繪 | `n_hg_yilin` |

### 7.3 選做：新怪物（8 張）

沒有也沒關係，現在借用山賊、野狼、守城官兵等舊圖。沒列在這裡的新怪（武當黑玉的七蟲七獸、峨嵋連環殺人案的惡人等）也先借舊圖，之後一起補。

| 檔名 | 名稱 | 描述 | 目前借用 |
|---|---|---|---|
| `unit_m_dl_mingjiao_idle.png` | 明教分舵主 | Same Ming Cult branch leader as n_dlw_guiyi in battle stance, white robe flaring, curved sabre (彎刀) drawn, red flame emblem on chest; wuxia RPG battle sprite. | `m_bandit` |
| `unit_m_lf_wugong_idle.png` | 蜈蚣 | 赤紅色大蜈蚣，百足，鉗牙；斜 45 度 Q 版怪物 | `m_rabbit` |
| `unit_m_lf_zhizhu_idle.png` | 毒蜘蛛 | 拳頭大的花斑毒蜘蛛，八條長腿；斜 45 度 Q 版怪物 | `m_rabbit` |
| `unit_m_lf_qingshe_idle.png` | 青蛇 | 細長青蛇昂首吐信；斜 45 度 Q 版怪物（可沿用毒蛇圖改色） | `m_wolf` |
| `unit_m_lf_xiezi_idle.png` | 蝎子 | 黑亮蝎子尾鉤翹起；斜 45 度 Q 版怪物（可沿用毒蠍圖） | `m_rabbit` |
| `unit_m_hn_mojiao_idle.png` | 魔教教徒 | 魔教教徒：黑巾裹頭、黑色勁裝、手持鬼頭刀的兇悍漢子。 | `m_bandit` |
| `unit_m_xx_laodenuo_idle.png` | 勞德諾 | 同 n_xx_laodenuo，拔劍戰鬥立繪 | `n_xx_laodenuo` |
| `unit_m_ym_qiangdao_idle.png` | 強盜 | 同 n_ym_qiangdao，戰鬥立繪 | `m_bandit` |

### 7.4 之後才需要的（現在先不用產）

- **尋找楊康、幫助陳大寶、其他 2001 事件**（`ev_yangkang`、`ev_chendabao`、`ev_misc_2001`）：內容已完成（故事包已整合；M3B_PLAN E10），需要的圖已列在第四批（第 7 節）與第五批（第 8 節）。
- **遊蕩惡人南海鱷神、葉二娘的戰鬥圖**（`m_nanhai`、`m_yeerniang`）：現在直接借用他們的 NPC 圖。

---

## 8. 第五批（2026-10-20 新增，M3b：丐幫、京城、絕情谷、高昌、雁門關、馬王洞）

M3b 開了**神鵰大俠（1.0B）**的內容：第 11 派**丐幫**（京城北郊山路上的破廟）、完整的**京城**（廣場、錢莊、中華鏢局、衙門、京城監獄、天地會香堂、北門）、**絕情谷**與谷底地牢；1.0A 也補了**馬王洞**（雁門關西邊）、**高昌古道、高昌、高昌迷宮**，西夏、大理多了錢莊、鏢局、打鐵舖、布莊。新 NPC 與新怪現在全部借用舊圖頂著（`data/art.json` 的 `alias`，右欄是目前借的圖），**缺的都不會壞**。下面照優先順序排列，做多少算多少。

> 放的位置和前幾批一樣：`assets\art_in\`，檔名照下表。放好跟我說一聲，我把 `data/art.json` 裡那一條的 `alias` 換成正式圖。
> 每張一樣先貼第 0 節的風格說明；人物、怪物再加第 0 節第二段。

### 8.1 丐幫服裝（2 張，最優先）

規格同第 2 節。現在丐幫弟子穿的是布衣（`player_m`／`player_f`）。

| 檔名 | 角色 | 描述 | 目前借用 |
|---|---|---|---|
| `unit_gaibang_m_idle.png` | 丐幫弟子・男 | Young male Beggars' Sect (丐幫) disciple: patched hundred-piece robe (百衲衣) in faded brown and grey cloth, straw sandals, small cloth sacks tied at the waist, holding a green bamboo staff, messy hair tied with a cloth strip, bold cheerful expression. | `player_m` |
| `unit_gaibang_f_idle.png` | 丐幫弟子・女 | Young female Beggars' Sect disciple: patched hundred-piece robe, straw sandals, hair loosely tied up with a cloth strip, a smudge of dust on her cheek but bright clever eyes, holding a green bamboo staff. | `player_f` |

### 8.2 新地區戰鬥背景（12 張）

規格同第 1 節：**1920×1080 PNG**，斜上方約 30 度俯視，**中央約 70% 是平坦空地**，裝飾只放邊緣，不要人物、動物、文字。最後兩張（京城監獄、天地會香堂）是**房間**不是地區，現在遊戲還不會用到，先做前十張。

| 檔名 | 地區 | 描述 | 目前借用 |
|---|---|---|---|
| `bg_jingcheng.png` | 京城 | Wide paved stone square inside the ancient Chinese capital: grey flagstones, a stone lion pair and a flagpole at the edges, two-storey shopfronts with hanging signboards and red lanterns along the back edge, a distant glimpse of yellow palace roofs. Bright daylight. | `jingcheng_wild` |
| `bg_jingcheng_wild.png` | 京城南郊 | （第 1 節已有；如果想重畫）Green farmland crossroads south of the capital, worn stone road, willows, low earthen wall. | （已有正式圖） |
| `bg_jingcheng_north.png` | 京城北郊 | Barren yellow-earth mountain road north of the capital: an old gnarled pagoda tree, loose rocks and boulders along the edges, wild grass, bleak distant ridges and a dark forest line, cold windy light. | `jingcheng_wild` |
| `bg_gaibang.png` | 丐幫破廟 | Courtyard of a ruined mountain temple used by beggars: cracked flagstones, a broken stone incense burner, piles of straw and a smouldering campfire at the edges, a crumbling temple hall with a half-collapsed roof along the back edge, bamboo staffs leaning on a wall. | `shaolin` |
| `bg_jueqinggu.png` | 絕情谷 | Deep secluded mountain valley full of blooming passion-flower bushes (red and white blossoms on thorny branches) along the edges, a clear stream, a grey stone house half-hidden at the back edge, soft misty light. | `gumu` |
| `bg_jueqinggu_dilao.png` | 絕情谷地牢 | Underground dungeon beneath the valley: damp stone floor, iron-barred cells and rusty chains along the walls, a black cold pool with crocodile backs breaking the surface at one edge, a single shaft of light from above. | `gumu_maze` |
| `bg_mawang.png` | 馬王洞 | Large bandit cave inside a mountain: rough rock floor, a campfire, stacked wine jars and iron rings for tethering horses along the walls, a tiger pelt spread near the back, flickering orange light. | `guiwang` |
| `bg_gaochang_road.png` | 高昌古道 | Gravel gobi caravan road where snowfields fade into desert: scattered pebbles and camel-thorn, a felt caravan tent and a stone well at the edges, distant snowy peaks, pale cold sunlight. | `desert_edge` |
| `bg_gaochang.png` | 高昌 | Ruins of the ancient desert city of Gaochang: half-buried rammed-earth walls and a crumbling city gate arch along the back edge, wind-swept sand, a few dead poplar trees, harsh afternoon light. | `desert_edge` |
| `bg_gaochang_maze.png` | 高昌迷宮 | Underground mud-brick maze: narrow earthen corridors opening into a flat chamber, faded Buddhist murals on the walls, bronze pipes and gear mechanisms protruding at the edges, dim lamp light. | `guiwang` |
| `bg_jc_jail.png` | 京城監獄（房間，之後才用） | Gloomy stone prison cell: a tiny iron-barred window letting in one beam of light, mouldy straw on the floor, chains on the walls, a heavy wooden door at the back edge. | — |
| `bg_jc_tdh_hall.png` | 天地會香堂（房間，之後才用） | Secret society shrine room hidden behind a coffin shop: a wooden altar with a blank memorial tablet (no text), an incense burner with drifting smoke, tall candlesticks on both sides, dark red drapes. | — |

### 8.3 NPC 立繪（對話框左邊；20 張，師父與任務給予者優先）

| 檔名 | 角色 | 描述 | 目前借用 |
|---|---|---|---|
| `unit_n_gb_chen_idle.png` | 陳長老 | Old beggar elder with white hair and beard, six small cloth sacks hanging on his back, leaning on a bamboo staff, sharp piercing eyes, patched robe. | `player_m` |
| `unit_n_gb_chuangong_idle.png` | 傳功長老 | Lean old beggar elder sitting cross-legged on a straw mat, one hand forming a meditation mudra, bamboo staff resting beside him, calm wise expression. | `player_m` |
| `unit_n_gb_zhanggun_idle.png` | 掌棍長老 | Burly old beggar elder gripping a heavy black iron rod planted on the ground, thick eyebrows, glaring angry eyes, patched robe with rolled sleeves. | `player_m` |
| `unit_n_gb_jiang_idle.png` | 姜乞丐 | Old beggar sitting on stone steps in front of a bank, holding out a chipped bowl, one ear cocked to listen, sly knowing eyes. | `player_m` |
| `unit_n_tdh_chenjinnan_idle.png` | 陳近南 | Scholar-leader about forty in a plain blue-green long robe and square cloth cap, hands clasped behind his back, kind yet commanding expression (head of the Heaven and Earth Society). | `n_chenjialuo` |
| `unit_n_jq_gongsunzhi_idle.png` | 公孫止 | Lean refined man about fifty in a plain grey-green scholar robe, neatly trimmed beard, courteous smile but cold calculating eyes, master of Passionless Valley. | `n_yuebuqun` |
| `unit_n_jq_lve_idle.png` | 公孫綠萼 | Gentle young woman in a pale green silk dress, hair in a simple bun with a jade pin, standing beside an alchemy furnace holding a small medicine bottle, kind worried expression. | `n_shuanger` |
| `unit_n_jq_qiuqianchi_idle.png` | 裘千尺 | Bald gaunt old woman with crippled legs sitting on a cave floor in ragged clothes, fierce glittering eyes, a jujube pit between her lips, bitter grin. | `n_yeerniang` |
| `unit_n_jq_liumei_idle.png` | 柳姑娘 | Ethereally beautiful young woman in flowing pure white robes, long black hair, cool aloof melancholy expression, looking out of a study window. | `n_shuanger` |
| `unit_n_mj_fanyao_idle.png` | 范遙 | Middle-aged ascetic monk (頭陀) with a disfigured face covered in scars, loose long hair, grey-brown robe tied with hemp rope, sitting on a rock, cold silent stare. | `n_xx_wushi` |
| `unit_n_ym_miaorenfeng_idle.png` | 苗人鳳 | Gaunt tall swordsman with a sallow face, long sword on his back, grey cloth robe flapping in the frontier wind, lonely solemn expression. | `n_chenjialuo` |
| `unit_n_ym_azhu_idle.png` | 阿朱 | Pretty girl about seventeen in a light pink jacket and skirt, hair in twin buns, leaning on a wall and gazing into the distance, gentle anxious eyes. | `emei_f` |
| `unit_n_gc_xiangxiang_idle.png` | 香香公主 | Innocent breathtakingly beautiful Uyghur princess in a white dress, a green kingfisher feather in her hair, long braids, butterflies fluttering around her. | `n_em_yingyueer` |
| `unit_n_gc_huoqingtong_idle.png` | 霍青桐 | Heroic Uyghur woman warrior in a yellow robe with a green sash, a green feather on her cap, short sword at her waist, confident bright gaze. | `emei_f` |
| `unit_n_gc_jilaoren_idle.png` | 計老人 | Hunched old Han Chinese man in a sheepskin coat holding a bowl of milk tea, deep thoughtful eyes, weathered face. | `n_taoyun` |
| `unit_n_gc_liwenxiu_idle.png` | 李文秀 | Han Chinese girl in Kazakh dress with an embroidered cap and long braids, leaning in a doorway and singing softly, lonely wistful expression. | `n_em_jinxiaomei` |
| `unit_n_xx_zhangtie_idle.png` | 張鐵 | Broad-shouldered ironmonger in his thirties, soot-smudged face, leather apron, holding a smithing hammer beside an anvil. | `n_xx_smith` |
| `unit_n_ec_xx_banker_idle.png` | 錢莊老闆 | Middle-aged merchant in a silk long gown and skullcap, one hand resting on an abacus, shrewd polite smile. | `n_xx_innkeeper` |
| `unit_n_ec_xx_biaotou_idle.png` | 鏢頭 | Burly escort-agency chief with tiger back and bear waist, short fighting jacket, broad-backed saber at his hip, an escort pennant planted behind him. | `n_xx_wushi` |
| `unit_n_jc_jailer_idle.png` | 監獄看守人 | Brutish prison warden with a fleshy face, black uniform with a red sash, a big ring of iron keys at his waist, holding a short club. | `n_dl_bukuai` |

（同一張圖可以給同職務的 NPC 共用：大理、京城的錢莊老闆與鏢頭先借西夏那兩張。）

### 8.4 選做：新怪物（11 張）

沒有也沒關係，現在借用野狼、山賊、山賊頭目、少林銅人等舊圖。

| 檔名 | 名稱 | 描述 | 目前借用 |
|---|---|---|---|
| `unit_m_gb_xiaohuang_idle.png` | 小黃 | Scrawny little yellow street dog, teeth bared, barking and lunging forward. | `m_wolf` |
| `unit_m_gb_xiejiao_idle.png` | 邪教門徒 | Cultist in black clothes with a black face mask, steel saber raised, battle stance. | `m_bandit` |
| `unit_m_gb_manbing_idle.png` | 蠻兵 | Fierce barbarian soldier with high nose and deep-set eyes, fur and leather armour, swinging a huge mountain-cleaving saber. | `m_bandit_chief` |
| ~~`unit_m_jcn_mazeiwang_idle.png`~~ | 馬賊王 | （2026-10-20 審查：與馬王合併成 `m_mw_mawang`，用下面那張 `unit_m_mw_mawang_idle.png`，這張不用畫） | — |
| `unit_m_jcn_huguo_idle.png` | 護國法師 | Foreign lama in a red kasaya, both palms thrust forward in a martial strike, cold sneer. | `m_bandit_chief` |
| `unit_m_jcn_shafeng_idle.png` | 煞風寨寨主 | Big bandit-fortress chief swinging a ghost-head saber, fur cape, wild hair. | `m_bandit_chief` |
| `unit_m_jcn_yinmian_idle.png` | 隱面人 | Mysterious figure with a black gauze veil over the face, dark robe, saber held low, silently stalking. | `m_bandit` |
| `unit_m_jq_eyu_idle.png` | 鱷魚 | Huge dark crocodile emerging from a black underground pool, jaws wide open, wet armoured scales. | `m_boar` |
| `unit_m_jq_fanyiweng_idle.png` | 樊一翁 | Very short old man with an absurdly long grey beard whipping through the air like a lash, heavy steel staff raised. | `m_bandit_chief` |
| `unit_m_mw_mawang_idle.png` | 馬賊王（人稱馬王） | Burly bandit chief in yellow brass scale armour, big saber, full beard, standing in a cave. | `n_bandit_chief` |
| `unit_m_gc_jiguanren_idle.png` | 機關人 | Ancient wooden automaton with bronze arms, exposed gears at the joints, Central Asian Buddhist-cave style carvings, rigid fighting pose. | `m_sl_tongren_3` |

### 8.5 之後才需要的（現在先不用產）

- **生活技能的工具與材料圖示**（十字鎬、採沙器、打鐵鎚、鋸子、針線包；鐵礦石、鐵塊、木炭、焦炭、麻、棉花、線軸、布、獸皮、皮革等）：等介面有物品圖示位置再說。
- **鏢車**（`n_ec_biaoche`，兩匹騾子拉的木車，車上箱籠蓋油布、插三角鏢旗）：護送時跟在玩家身邊，現在借驛站的圖。
- **其他借舊圖的新 NPC 與怪**（大理、京城的錢莊老闆與鏢頭、組織書吏、京城街坊、天地會管事、北郊的馬賊頭子、道人頭子、惡道人頭子，絕情谷綠衣弟子、地牢水蛇與囚徒，高昌惡賊、銅甲機關人，打獵用的野獸，未做的 2001 事件的 NPC 與毒物）：前面的做完再說。

---

## 9. 初始造型（2026-10-20 新增；創角時可以選）

> **狀態（2026-10-20，M3c）**：16 張 idle 與收到的出招／受傷圖都已登記（`look_m01..08`、`look_f01..08`，比例 1.0）；創角畫面右半邊的造型選擇器、屬性窗「更換造型」已做好。

創角時可以挑一個**初始造型**，未入派前的戰鬥外觀和對話框裡的立繪都用這張。拜入門派後照舊換成門派服裝（第 2、6 節）。現有的 `player_m`／`player_f`（布衣）保留，當作第 0 號造型。

**一律先貼第 0 節兩段說明**（風格說明，加上人物那段：透明背景、全身、面向左下、1024×1024），再接下面的描述。同一位角色想做出招、受傷動作時，在**同一個對話**裡說「same character, now attacking / now hurt」，檔名把 `_idle` 換成 `_attack`／`_hurt`（選做）。

> 放的位置一樣：`assets\art_in\`。功能做好前先放進去也沒關係，我會一起登記。

### 9.1 男性造型（8 張）

| 檔名 | 造型 | 描述 |
|---|---|---|
| `unit_look_m01_idle.png` | 書生 | Young scholar-swordsman, pale blue long scholar robe, square scholar cap, holding a folding fan in one hand and a sheathed sword in the other, gentle refined face. |
| `unit_look_m02_idle.png` | 獵戶 | Rugged young hunter, sleeveless brown leather vest over a coarse shirt, fur trim, a bow on his back and a hunting knife at the belt, messy short hair tied back, sun-tanned face. |
| `unit_look_m03_idle.png` | 浪子 | Carefree wandering swordsman, loose dark grey robe worn open at the chest, a gourd of wine at his waist, long hair half tied, lazy confident grin, sword resting on his shoulder. |
| `unit_look_m04_idle.png` | 少年俠客 | Eager teenage boy in a short red-and-black martial jacket, cloth headband, wooden sword, bright determined eyes. |
| `unit_look_m05_idle.png` | 壯漢 | Big burly young man, bare muscular arms, sleeveless dark blue tunic, wide leather belt, heavy iron-bound staff, thick eyebrows, honest face. |
| `unit_look_m06_idle.png` | 刀客 | Lean cold-eyed young blade-wielder, black tight-fitting martial clothes, red sash, single-edged dao sabre held low, a thin scar on one cheek. |
| `unit_look_m07_idle.png` | 富家公子 | Young nobleman in an elegant white-and-gold brocade robe, jade pendant at the waist, hair in a neat topknot with a silver crown, fine jian sword, slightly arrogant smile. |
| `unit_look_m08_idle.png` | 西域旅人 | Young traveler from the western regions, sand-colored wrapped robes, a cloth head wrap and scarf, curved sabre, sharp eyes, weathered by desert wind. |

### 9.2 女性造型（8 張）

| 檔名 | 造型 | 描述 |
|---|---|---|
| `unit_look_f01_idle.png` | 俠女 | Young swordswoman in a light green martial dress, hair in a high ponytail with a ribbon, straight sword in hand, bright resolute expression. |
| `unit_look_f02_idle.png` | 村姑 | Cheerful village girl in a plain floral cotton jacket and trousers, two braids, a basket on her arm and a small knife at her waist, rosy cheeks. |
| `unit_look_f03_idle.png` | 千金小姐 | Young lady from a wealthy family, elegant pink-and-white layered silk dress, hair in an ornate bun with hairpins, holding a round silk fan, a slim dagger hidden in her sleeve. |
| `unit_look_f04_idle.png` | 江湖女子 | Sharp-tongued wandering woman of the rivers and lakes, dark red short jacket, black trousers, leather bracers, a whip coiled at her waist, confident smirk. |
| `unit_look_f05_idle.png` | 少女 | Young teenage girl in a light yellow dress, hair in two side buns, holding a short wooden sword, curious lively eyes. |
| `unit_look_f06_idle.png` | 女刀客 | Tall cold woman warrior in black-and-grey martial clothes, hair tied in a tight bun, single-edged dao sabre, stern unsmiling face. |
| `unit_look_f07_idle.png` | 醫女 | Gentle young herbalist in a light teal robe, a medicine pouch and small gourd at her belt, hair half up with a wooden hairpin, holding a bundle of herbs and a short sword. |
| `unit_look_f08_idle.png` | 苗疆少女 | Young Miao girl in an indigo embroidered dress, silver headdress and silver bracelets, barefoot, a small bamboo flute at her waist, mischievous smile. |

### 9.3 小提醒

- **同一批一起畫**：16 張最好在同一個 ChatGPT 對話裡連續產生，畫風會比較一致。可以在第一張之前先說「I will ask for 16 characters in the same art style; keep the style identical for all of them」。
- **臉要看得清楚**：創角畫面會放大顯示，臉部細節比戰鬥圖重要。
- **全身入鏡、腳底在畫面底部中間**：戰鬥時是以腳底對齊格子。
- 只產 `_idle` 就夠了；`_attack`／`_hurt` 有的話戰鬥會更生動。

---

## 10. 地圖美術（2026-10-20 新增；大地圖、區域圖、小地圖）

> **狀態（2026-10-20，M3c）**：程式已就緒、圖還沒到。`data/art.json` 的 `map`／`map_icons` 區塊已登記（`placeholder: true`）；`tools/import_art.py` 認得 `map_*.png`。圖放進 `assets\art_in\` 後跑 `python -I tools/import_art.py` 與 `python -I tools/art_register.py . --only "map_*"` 就會換上（全圖底圖照 `make_map_layout_guide.py` 的轉換對位）；沒有圖時照舊用程式畫的羊皮紙地圖。

現在的地圖是程式畫的方框加線條，看起來很陽春。這一批讓 ChatGPT 畫**底圖、節點框、圖示**，地點、路線、文字還是由遊戲疊上去，所以位置永遠對得準。

> 檔案一樣放 `assets\art_in\`，檔名照下表。圖示類都是**透明背景 PNG**。
> 這一批是**地圖插畫風**，不用貼第 0 節的人物說明，改貼下面這段：

```
Style: hand-painted antique Chinese map, ink-wash and light mineral colors on aged
parchment / xuan paper, like a Ming-dynasty illustrated atlas (山水輿圖). Soft brush
strokes, muted earth tones, subtle paper texture. Consistent style across all images.
No text, no characters, no labels, no modern elements.
```

### 10.1 江湖全圖底圖（1 張，最重要）

**一定要附上構圖參考圖**：把 `docs\map_layout_guide_nolabel.png` 上傳給 ChatGPT（`docs\map_layout_guide.png` 是有地名的版本，給你自己對照）。參考圖的位置是照原作 2001 座標算的，遊戲會把地點標記疊在同樣的位置。

| 檔名 | 規格 | 描述（接在上面那段風格說明後面） |
|---|---|---|
| `map_world_base.png` | **2400×1800**（4:3，一定要這個比例） | Repaint the attached layout guide as a beautiful antique Chinese map of the martial world. KEEP every terrain zone exactly where it is in the guide: desert (tan) in the north-west and west, snowy mountains (white) at the top-left and on the far west, a central mountain range (grey-green) in the middle-right, forests (green) in the south-centre and near the top-right, a lake (blue) at the bottom-left, rivers along the blue lines. Each circle in the guide marks a place: leave a small open, flat clearing at every circle (no buildings, no symbols there), because the game draws its own city seals and markers on top. Add gentle mountains, dunes, trees and waves as painted texture. Fill the empty areas with soft parchment and faint clouds. No text, no compass, no border. |

> 生成後請看一下：圓圈的位置有沒有被畫上建築或文字？有的話請 ChatGPT 「keep those spots empty」重產。位置差一點點沒關係，我疊上去時會微調。

### 10.2 區域圖／小地圖的底與房間框（5 張）

| 檔名 | 規格 | 描述 |
|---|---|---|
| `map_region_bg.png` | 1024×1024，**可無縫拼接** | Seamless tileable aged parchment texture with very faint ink cloud patterns, light and calm so text on top stays readable. |
| `map_node_room.png` | 384×192，透明背景 | A rectangular map room plaque: light parchment fill, thin dark-ink brush border with slightly rounded corners, empty inside (the game writes the room name). |
| `map_node_current.png` | 384×192，透明背景 | Same plaque as map_node_room, but with a bold vermilion-red brush border and a faint warm glow, marking the player's current location. Empty inside. |
| `map_node_fog.png` | 384×192，透明背景 | The same plaque shape covered by soft grey ink mist/clouds, mysterious, for an unexplored room. Empty inside. |
| `map_marker_here.png` | 256×256，透明背景 | A small vermilion seal-style map pin / pennant flag marking "you are here", clean silhouette. |

### 10.3 地圖圖示（16 張，256×256，透明背景，同一套畫風）

一律用：`Single small map icon, centered, transparent background, flat-ish brush-painted style with a thin dark outline, readable at 32 pixels.` 接下面的描述。

| 檔名 | 用途 | 描述 |
|---|---|---|
| `map_icon_city.png` | 城市 | A tiny walled Chinese city gate with a red-roofed tower. |
| `map_icon_sect.png` | 門派 | A small mountain temple / pagoda on a peak. |
| `map_icon_cave.png` | 洞窟、迷宮 | A dark cave mouth in a rocky hill. |
| `map_icon_wild.png` | 野外 | Two small pine trees on a grassy mound. |
| `map_icon_station.png` | 驛站 | A galloping post horse with a small banner. |
| `map_icon_inn.png` | 客棧 | A hanging red paper lantern with an inn sign. |
| `map_icon_shop.png` | 商店 | A traditional Chinese hand scale with coins. |
| `map_icon_master.png` | 師父 | A thread-bound martial arts manual with a brush. |
| `map_icon_record.png` | 查小鏞（記錄點） | An open ledger book with a writing brush. |
| `map_icon_field.png` | 田 | A small rice paddy with sprouts. |
| `map_icon_wood.png` | 林（砍柴） | A woodcutter's axe stuck in a log. |
| `map_icon_water.png` | 水（釣魚） | A fishing rod over small waves. |
| `map_icon_stove.png` | 灶（廚師） | A clay stove with a wok and steam. |
| `map_icon_danger.png` | 會遇敵 | Two crossed swords with a small red splash. |
| `map_icon_quest.png` | 任務目標 | A rolled scroll tied with a red ribbon and a small exclamation-like brush mark. |
| `map_icon_exit.png` | 通往別區的出口 | A brush-painted arrow along a small road. |

### 10.4 選做：裝飾

| 檔名 | 規格 | 描述 |
|---|---|---|
| `map_compass.png` | 512×512，透明背景 | An antique Chinese compass rose (羅盤) in ink and gold, eight directions, no text. |
| `map_frame_title.png` | 1024×256，透明背景 | An ornamental title cartouche: a horizontal scroll banner with ink-painted dragon or cloud borders, empty in the middle for the map title. |

---

## 11. 空手人物＋武器特效（2026-10-20 決定；取代人物圖上畫死的武器）

> **狀態（2026-10-20，M3c）**：32 張空手玩家圖（idle／attack／hurt）已匯入、同檔名覆蓋；被覆蓋的舊圖備份在 `K:\Project\JY-Mini-OL-Work\art_backup\2026-10-20\`（另有空手重畫前的完整快照 `snapshot_units\`，214 檔）。12 張武器特效（`fx_weapon_*`、`fx_skill_*`）與 6 個武器小圖示（`icon_weapon_*`）已登記並在戰鬥中使用；缺圖的種類用程式畫的備援。

**為什麼要重畫**：人物圖手上的武器是畫死的（武當拿劍、布衣拿木刀），玩家換了單刀、竹棒或空手練拳時，圖就對不上。改成：**玩家角色一律畫成空手**，出招時由遊戲依「實際裝備的武器類型」疊上武器特效（劍光、刀弧、棍影、鞭影、掌勁），名牌旁顯示武器小圖示。這樣不管換什麼武器都對得上，以後加新武器也不用再畫人。

**只有玩家角色要重畫。** NPC 立繪和怪物照舊，他們的武器是固定的。

### 11.0 做法（重要：保持同一個人）

1. 每個角色開一個 ChatGPT 對話（或沿用當初畫他的那個對話）。
2. **上傳原本那張 idle 圖**（在 `assets\art_in\` 裡，例如 `unit_wudang_m_idle.png`）。
3. 先貼第 0 節兩段說明，再貼下面這段：

```
Redraw this exact same character — same face, hairstyle, clothing, colors and art
style — but EMPTY-HANDED: no weapon in the hands, and no weapon anywhere on the body
(no sword on the back, no scabbard, no staff, no whip at the waist).
```

4. 接著依姿勢加一句：

| 姿勢 | 加這一句 |
|---|---|
| `idle`（站姿） | `Calm ready martial-arts stance, hands empty and relaxed, one hand slightly forward.` |
| `attack`（出招） | `Dynamic lunging strike toward the lower-left, the leading arm fully extended forward with the hand in a loose fist as if striking, body leaning into the attack.` |
| `hurt`（受傷） | `Recoiling backward from a hit, one arm raised defensively, hands empty, pained expression.` |

5. **檔名跟原本一模一樣**（例如還是 `unit_wudang_m_idle.png`），放進 `assets\art_in\` 直接覆蓋。舊圖我匯入前會先備份到 `K:\Project\JY-Mini-OL-Work\`，不會遺失。
6. 出招圖的「伸出去的那隻手」要清楚：遊戲會從那附近畫出武器特效。

### 11.1 要重畫的玩家角色（32 位 × 3 個姿勢）

**優先順序**：先把 32 張 `idle` 全部做完（遊戲裡最常看到），再做 `attack`，最後 `hurt`。每一階段做完都可以先放進來，缺的姿勢遊戲會用 idle 加程式動畫頂著。

| 類別 | 檔名前綴（後面接 `_idle`／`_attack`／`_hurt`） | 數量 |
|---|---|---|
| 布衣（未入派） | `unit_player_m`、`unit_player_f` | 2 |
| 初始造型 | `unit_look_m01` … `unit_look_m08`、`unit_look_f01` … `unit_look_f08` | 16 |
| 門派服裝 | `unit_shaolin_m`、`unit_huashan_m`、`unit_huashan_f`、`unit_wudang_m`、`unit_quanzhen_m`、`unit_xuedao_m`、`unit_xingxiu_m`、`unit_xingxiu_f`、`unit_emei_f`、`unit_hengshan_f`、`unit_gumu_f`、`unit_lingjiu_f` | 12 |
| 丐幫（第 8.1 節還沒畫的） | `unit_gaibang_m`、`unit_gaibang_f` | 2 |

> 丐幫還沒畫：**直接照 8.1 的描述畫成空手版**（把描述裡拿棍子的部分拿掉，接上 11.0 的空手句子），就不用重畫了。
> 以後新增的門派服裝、造型，一律照這一節畫成空手。

### 11.2 武器特效（12 張，最重要的是前 5 張）

規格：**1024×512 PNG、透明背景**、橫向，**特效從左邊（手的位置）往右邊揮出**（遊戲會依方向翻轉、旋轉）。只畫特效本身，不要人、不要武器實體以外的東西。先貼這段：

```
Single martial-arts weapon effect for a 2D game, transparent background, wide
horizontal image 1024x512, the effect starts at the LEFT edge (where the hand is)
and sweeps toward the right. Painterly wuxia style matching early-2000s Taiwanese
online RPGs, glowing but not neon. No character, no text.
```

| 檔名 | 武器類型 | 描述 |
|---|---|---|
| `fx_weapon_sword.png` | 劍（SWORD） | A slender straight jian sword blade visible at the start, followed by a thin, fast silver-white crescent slash trail with a sharp tip, elegant. |
| `fx_weapon_blade.png` | 刀（BLADE） | A broad single-edged dao sabre at the start, followed by a heavy, wide arc of cold steel-blue light, powerful and chopping. |
| `fx_weapon_staff.png` | 棍杖（STAFF） | A long wooden staff motion-blurred through a wide sweeping half-circle, with dust and wind lines. |
| `fx_weapon_whip.png` | 鞭（WHIP） | A leather whip lashing out in an S-shaped curl, ending in a sharp crack spark. |
| `fx_weapon_fist.png` | 拳掌（FIST，空手） | A golden-orange palm-shaped burst of inner energy shooting forward, with concentric shockwave rings. |
| `fx_weapon_claw.png` | 爪（木爪等） | Three parallel red-brown claw slash marks tearing forward. |
| `fx_weapon_stab.png` | 刺（STAB） | A single piercing point-thrust: a narrow bright line ending in a star-shaped flash. |
| `fx_weapon_hidden.png` | 暗器（HIDDEN） | Several small flying darts and throwing needles streaking forward with faint trails. |
| `fx_skill_inner.png` | 內功 | A swirling burst of pale blue-white inner qi spiralling forward. |
| `fx_skill_poison.png` | 毒 | A cloud of sickly green poison mist with tiny dark particles drifting forward. |
| `fx_skill_medic.png` | 醫（療傷） | Soft rising green healing light with small leaf-like sparkles (not a slash; gentle). |
| `fx_skill_formation.png` | 陣（陣法） | A faint golden circular ground pattern of trigram (八卦) lines, seen from slightly above. |

### 11.3 武器小圖示（6 張，名牌旁顯示「拿著什麼」）

規格：256×256、透明背景，先貼這段：`Single small weapon icon, centered, transparent background, brush-painted wuxia style with a thin dark outline, readable at 24 pixels.`

| 檔名 | 描述 |
|---|---|
| `icon_weapon_sword.png` | A straight jian sword, diagonal. |
| `icon_weapon_blade.png` | A single-edged dao sabre, diagonal. |
| `icon_weapon_staff.png` | A wooden staff, diagonal. |
| `icon_weapon_whip.png` | A coiled leather whip. |
| `icon_weapon_claw.png` | A wooden claw gauntlet. |
| `icon_weapon_fist.png` | A clenched fist (bare hands). |

### 11.4 數量總結

| 項目 | 張數 | 優先 |
|---|---|---|
| 32 位玩家角色 `idle`（空手） | 32 | 最優先 |
| 武器特效前 5 張（劍、刀、棍、鞭、拳） | 5 | 最優先 |
| 武器小圖示 | 6 | 高 |
| 32 位玩家角色 `attack` | 32 | 中 |
| 其餘 7 張特效 | 7 | 中 |
| 32 位玩家角色 `hurt` | 32 | 低 |

---

## 12. 第六批（2026-10-21 新增，M3d：懸賞與律法、合體技、武功鏈、比武與劫鏢、跑腿、黑龍潭）

M3d 加了**衙門懸賞**（佈告欄、官爺、天師、京城半仙、賞金獵人）、**合體技**與兩件稀有道具（無敵烙跑鞋、夜明珠）、全真／靈鷲／峨嵋／星宿／血刀的**武功鏈**、**門派比武與武林大會**、**危險鏢與劫鏢**，
以及**跑腿**（柯鎮惡→郭靖、豬哥義→三八紅、武林帖、送便當、酒鬼、阿虎與青青）和 1.0B 的小區域**黑龍潭**。
新 NPC 裡有一部分借用舊圖（右欄），**沒有右欄的現在用程式畫的暫代人形**；缺圖都不會壞。照優先順序排，做多少算多少。

> 放的位置和前幾批一樣：`assets\art_in\`，檔名照下表。放好跟我說一聲，我把 `data/art.json` 那一條換成正式圖。
> 每張一樣先貼第 0 節的風格說明；人物、怪物再加第 0 節第二段。

### 12.1 NPC 立繪（對話框左邊；最優先的 12 張）

天天會看到的：佈告欄旁的兩位官爺、天師、半仙、鏢局二掌櫃、比武報名員，還有跑腿的主角。

| 檔名 | 角色 | 描述 | 目前借用 |
|---|---|---|---|
| `unit_n_law_guanye_a_idle.png` | 官爺（胖，發執照的那位；西夏、大理、京城共用） | Fat Chinese yamen constable in a black official robe with a red sash and a black gauze cap, big round belly, one hand holding a rolled-up wanted notice, smug self-important expression, standing beside a wooden notice board. | 暫代人形 |
| `unit_n_law_guanye_b_idle.png` | 官爺（瘦，耳聾的那位；三城共用） | Skinny bamboo-pole thin yamen constable in a slightly too-large black official robe and black gauze cap, picking his ear with his little finger, head tilted, squinting as if he did not hear what you said, comically confused. | 暫代人形 |
| `unit_n_law_tianshi_idle.png` | 天師（西夏、大理共用） | Taoist exorcist master in a yellow-and-black Taoist robe with eight-trigram patterns, tall Taoist hat, long beard, holding a peach-wood sword in one hand and a yellow paper talisman in the other, standing behind a small incense altar. | 暫代人形 |
| `unit_n_law_banxian_jc_idle.png` | 京城半仙 | Sly old fortune-teller with a thin goatee and small round dark glasses, sitting behind a fortune-telling table, a white cloth banner on a bamboo pole beside him (banner with NO text), holding a folding fan. | 暫代人形 |
| `unit_n_ev_jb_idle.png` | 鏢局二掌櫃（三城共用） | Lean middle-aged escort-agency deputy manager in a short dark fighting jacket, an abacus in one hand, a stack of escort contracts under his arm, shrewd calculating eyes, a broad-backed saber at his hip. | `n_xx_wushi` |
| `unit_n_ev_tourney_clerk_idle.png` | 比武報名員 | Elderly clerk in a grey scholar robe sitting at a desk with an open register, writing brush and ink stone, a blank wooden sign board behind him (NO text), patient tired expression. | `n_xx_innkeeper` |
| `unit_n_er_kezhene_idle.png` | 柯鎮惡 | Blind old martial artist with clouded white eyes, grizzled beard and scowling face, a heavy black iron staff planted in the snow, patched grey robe, head cocked to listen, standing in a snowfield. | 暫代人形 |
| `unit_n_er_guojing_idle.png` | 郭靖 | Broad-shouldered honest-looking man about thirty with thick eyebrows and big eyes, simple brown robe, standing on a bridge looking north, calm steady expression. | 暫代人形 |
| `unit_n_er_sanbahong_idle.png` | 三八紅 | Loud plump middle-aged shop owner woman in bright red and green clothes, a flower in her hair, hands on hips at a weaving loom, mouth open mid-gossip. | 暫代人形 |
| `unit_n_cb_jc_huolang_idle.png` | 西域貨郎 | Western Regions peddler with a high nose and deep-set eyes, colourful turban, carrying a gilded shoulder pole with two lacquered goods boxes full of exotic trinkets, sly friendly grin. | 暫代人形 |
| `unit_n_er_yinggu_idle.png` | 瑛姑 | Woman with white-streaked hair but a still youthful face, plain grey robe, sitting cross-legged amid scattered bamboo counting rods on the floor, intent cold expression, in a mud hut. | 暫代人形 |
| `unit_n_er_cien_idle.png` | 慈恩 | Huge old monk with a powerful build, grey kasaya, sitting in meditation on a dry patch in a swamp, eyes closed, suppressed fierce killing aura around him. | 暫代人形 |

### 12.2 NPC 立繪（武功鏈與跑腿；24 張）

| 檔名 | 角色 | 描述 | 目前借用 |
|---|---|---|---|
| `unit_n_ar_qz_shanju_idle.png` | 山居隱士（全真重陽劍法） | White-haired old hermit in coarse cloth squatting on a river beach watching the water, an ancient sword tucked in his belt. | 暫代人形 |
| `unit_n_ar_qz_shuliu_idle.png` | 漱流隱士 | Lazy hermit lying on a riverside rock with his head on the stream, one eye half-open, plain blue robe. | 暫代人形 |
| `unit_n_ar_qz_yunyou_idle.png` | 雲遊道士 | Wandering Taoist with a bamboo backpack basket, washing his feet in a small pool by a stone bridge, a horsetail whisk (拂塵) on his shoulder. | 暫代人形 |
| `unit_n_ar_qz_wangzhijin_idle.png` | 王志謹 | Calm young Quanzhen Taoist in a blue-grey Taoist robe copying a notice with a brush, indifferent detached gaze. | 暫代人形 |
| `unit_n_ar_lj_wuyazi_idle.png` | 無涯子 | Handsome old man with long white beard, paralysed legs, sitting in a hunter's hut corner, astonishingly clear bright eyes. | 暫代人形 |
| `unit_n_ar_ym_shouwei_idle.png` | 雁門關守衛 | Weather-beaten old frontier soldier in battered lamellar armour full of sword scars, spear in hand, scowling toward the frontier. | 暫代人形 |
| `unit_n_ar_guoxiang_idle.png` | 郭襄 | Young woman in a pale yellow robe sitting on a prayer cushion in a ruined temple, drinking from a wine cup, short sword at her waist, wistful lonely look. | 暫代人形 |
| `unit_n_ar_xd_xuemo_laozu_idle.png` | 血魔老祖 | Gaunt ancient Tibetan-style monk with blood-red skin and a crimson kasaya, sitting in a dark blood pool, terrifying calm smile. | 暫代人形 |
| `unit_n_ar_xd_baoxiang_idle.png` | 寶象 | Fat big-eared foreign monk in a red kasaya sitting on a hill gnawing a roast lamb leg, greasy grin. | 暫代人形 |
| `unit_n_ar_xd_inf_idle.png` | 血刀弟子（線人；兩位共用） | Shifty young Blood Blade sect monk in a red robe, saber at his hip, eyes darting around, leering grin. | 暫代人形 |
| `unit_n_ar_dingbusan_idle.png` | 丁不三 | Tall gaunt fierce old man in a dark grey robe, cruel smile, raising three fingers. | 暫代人形 |
| `unit_n_ar_dingbusi_idle.png` | 丁不四 | Old man who looks very much like 丁不三 but wears brown, raising four fingers, competitive pouting expression. | 暫代人形 |
| `unit_n_ar_laokelian_idle.png` | 老可憐 | Ragged old beggar crouching by a doorway holding out a chipped bowl, pitiful face but sly darting eyes. | 暫代人形 |
| `unit_n_ar_xd_xuechi_idle.png` | 血池弟子頭兒、護法、長老（共用一張） | Bare-chested muscular Blood Blade sect monk standing beside a blood-red pool, saber held with the back of the blade outward, challenging grin. | `n_ludayou`／`n_sl_huizhen` |
| `unit_n_er_tiefan_idle.png` | 武林帖販子 | Down-and-out scholar behind a small table piled with bright red invitation cards (NO text), waving one card and shouting. | 暫代人形 |
| `unit_n_er_xx_funv_idle.png` | 送便當的農婦 | Peasant woman with a blue cloth headscarf holding a covered bamboo lunch basket, looking out of a city gate. | 暫代人形 |
| `unit_n_er_xx_nongfu_idle.png` | 田邊農夫 | Peasant with rolled-up trousers standing in a muddy rice paddy, rice seedlings in hand, rubbing his hungry stomach. | 暫代人形 |
| `unit_n_er_dl_zuigui_idle.png` | 醉鬼 | Red-nosed drunkard slumped by a doorway hugging an empty wine jar, snoring, dishevelled clothes. | 暫代人形 |
| `unit_n_er_dl_ahu_idle.png` | 阿虎 | Honest shy young man in plain cloth clothes holding a crumpled letter, sighing. | 暫代人形 |
| `unit_n_er_dl_qingqing_idle.png` | 青青 | Pretty village girl washing clothes on riverside stone steps, a white narcissus flower tucked behind her ear, singing. | 暫代人形 |

（佈告欄 `n_law_board_*` 是物件，見 12.5。）

### 12.3 選做：新怪物（10 張）

| 檔名 | 名稱 | 描述 | 目前借用 |
|---|---|---|---|
| `unit_m_law_hunter_1_idle.png` | 賞金獵人 | Rough bounty hunter in a dark travelling cloak and leather bracers, a thick-backed saber in hand, a rolled wanted poster tucked in his belt, predatory grin. | `m_bandit` |
| `unit_m_law_hunter_2_idle.png` | 捕頭 | Yamen chief constable in a black uniform with red trim, official saber raised, an iron ruler (鐵尺) at his belt, stern face. | `n_dl_bukuai` |
| `unit_m_law_hunter_3_idle.png` | 神捕 | Legendary imperial detective in a dark blue robe swinging a chain-spear (鏈子槍) in a wide arc, cool unshakable expression. | `n_dl_bukuai` |
| `unit_m_ev_jb_bandit_idle.png` | 劫鏢山賊 | Masked highway robber with a black head scarf, blood-stained saber, ragged leather vest, lunging forward. | `m_bandit` |
| `unit_m_ev_jb_cart_idle.png` | 鏢車（危險鏢） | Heavy escort cart pulled by three mules, wooden crates sealed with paper strips, iron-plated sides, a triangular escort pennant on a pole (pennant with NO text). | `n_xx_station` |
| `unit_m_ev_jb_client_idle.png` | 客商 | Nervous merchant in a silk gown clutching a small wooden casket to his chest, a cloth bundle on his back, frightened eyes. | `n_xx_caishang` |
| `unit_m_er_wulin_idle.png` | 應帖的武林人士（四階共用） | Seasoned martial artist in a dark travelling robe with a red invitation card tucked in his belt, sword drawn, confident challenging pose. | `m_bandit`／`m_jcn_huguo`／`m_dl_cuisou`／`m_nanhai` |
| `unit_m_er_jiuwei_idle.png` | 九尾靈狐 | Small snow-white fox with nine fluffy tails fanned out behind it, glowing amber eyes, leaping mid-air. | `m_lj_xuehu` |
| `unit_m_er_yang_idle.png` | 羊 | Woolly grey-white mountain sheep with curled horns, chewing grass, bleating. | `m_npc_animal` |
| `unit_m_er_baiyuan_idle.png` | 白猿（沙漠山洞） | White-furred ape crouching on a rock scratching itself, curious but harmless look. | `m_wd_baiyuan` |

（羅煞劍任務的蠻兵 `m_ar_manbing` 用第 8.4 節的 `unit_m_gb_manbing_idle.png`；血池三階陪練 `m_ar_xd_xuechi_*` 先借血刀弟子 `m_xd_dizi`，有 12.2 的血池弟子圖就一起換。）

### 12.4 新戰鬥背景（2 張）

規格同第 1 節：**1920×1080 PNG**，斜上方約 30 度俯視，**中央約 70% 是平坦空地**，裝飾只放邊緣。

| 檔名 | 地區 | 描述 | 目前借用 |
|---|---|---|---|
| `bg_heilongtan.png` | 黑龍潭泥沼（1.0B） | Murky black-water swamp at the foot of a mountain: dark mud flats with scattered dry patches, reeds and dead trees at the edges, stones arranged in an eight-trigram pattern half-sunk in the mud, low mist, gloomy grey-green light. Center ground must stay flat and walkable. | `xixia_east` |
| `bg_biwu.png` | 西夏比武場擂臺 | Raised square wooden fighting stage (擂臺) in a city plaza, red-lacquered posts at the corners with silk ribbons, weapon racks and wooden benches for spectators at the edges, colourful festival banners (NO text), bright noon light. | （比武場的戰鬥現在用西夏城的背景） |

### 12.5 選做：地圖物件與道具圖示（之後才需要）

物品圖示和地圖物件現在介面還沒有位置，先列著，**現在先不用產**：

- **佈告欄**（`n_law_board_*`，地圖物件／對話框立繪）：a wooden notice board on two posts with a small tiled roof, covered in overlapping paper notices (NO readable text), one larger yellow paper in the center.
- **無敵烙跑鞋**（`i_cb_laopaoxie`）：light cloud-patterned black cloth boots with tiny wing motifs at the heels.
- **夜明珠**（`i_cb_yemingzhu`）：pigeon-egg-sized pearl glowing with soft cool light on a small silk cushion.
- **盟主令牌**（`i_ev_mengzhu_ling`）：pure gold token with a coiled dragon on the back (no readable text).
- **小木鼎**（`i_ar_xh_muding`）：palm-sized black wooden tripod cauldron with dark poison stains.
- **血魔刀訣**（`i_ar_xd_daojue`）：rolled sheepskin manuscript with blood stains.
- **羅煞劍**（`i_ar_luoshajian`）：slender long sword with a faint red sheen and a faded red silk tassel.
- 其他任務道具（狀元紅、兩封推薦信、黃藥丸、武林挑戰帖、便當、燒刀子酒、水仙、寬衣、包袱、靈狐血）：物品圖示做的時候一起畫。

### 12.6 數量總結

| 項目 | 張數 | 優先 |
|---|---|---|
| 12.1 每天看得到的 NPC | 12 | 最優先 |
| 12.2 武功鏈與跑腿 NPC | 20 | 中 |
| 12.3 新怪物 | 10 | 選做 |
| 12.4 戰鬥背景 | 2 | 中（黑龍潭先） |
| 12.5 物件與道具圖示 | — | 之後 |

---

## 13. 江湖試煉人物（2026-10-22 新增）

「江湖試煉」是新的肉鴿模式：每回合三選一，可以招名人當隊友，每 5 回合打一位名人首領。人物越多，這個模式越有味道，所以這次一口氣列了 **219 位**（名冊見 `docs/ROGUE_ROSTER.md`）。其中 **43 位已經有圖**，沿用；**176 位要新畫**，分三批：批次 A 16 位、批次 B 20 位、批次 C 140 位。缺圖不會壞，遊戲先用暫代圖頂著。

### 13.0 怎麼用 ChatGPT 畫（請先看）

1. **一位人物開一個新對話**，三個姿勢都在同一個對話裡畫完，臉、衣服、配色才會一致。
2. 先貼**第 0 節的兩段英文**（風格說明＋人物那段：透明背景、全身、面向左下、1024×1024），再貼下面該人物的中文描述。大小、比例、方向跟第 9、11 節的人物一樣：全身入鏡、腳底在畫面底部中間、約佔畫面高度 80%。
3. 第一張是站姿 `idle`：描述最後已經寫好「平靜的備戰站姿」。
4. 第二張出招 `attack`：在同一個對話說「同一個人，換成出招的姿勢：」再貼該人物的「出招」那一句。出招動作會暗示他的成名絕技，例如郭靖的龍形掌勁。
5. 第三張受傷 `hurt`：在同一個對話貼這句：

```
同一個人，換成受傷的姿勢：被擊中後身體向後仰，一手抬起護身，表情吃痛；衣服、髮型、配色、手上的兵器都不要變。透明背景，全身，面向左下。
```

6. **檔名**：`unit_rg_<代號>_idle.png`、`unit_rg_<代號>_attack.png`、`unit_rg_<代號>_hurt.png`，代號寫在每位人物的標題後面。全部放進 `K:\Project\JY-Mini OL\assets\art_in\`，去背、裁切、對齊我來處理。
7. **兵器**：這些人物是 NPC 一類的戰鬥單位（隊友和對手），兵器是固定的，所以**照描述畫在手上**；描述寫「空手」的就畫空手。這跟第 11 節「玩家角色一律空手」不同，第 11 節只管玩家角色。
8. **多人一張**：少林三渡、桃谷六仙、溫氏五老這類組合，戰鬥裡算一個單位，就把幾個人畫在同一張圖裡，前後錯開，整組仍然腳底在畫面底部中間。
9. 先做完批次 A 的 `idle`，再補 A 的 `attack`／`hurt`，然後才往 B、C。每做好一張都可以先放進來。

### 13.1 批次 A：首領與最有名的隊友（16 位，最優先）

每 5 回合的首領和玩家最想招的人，先畫這批。

#### 郭靖（射鵰英雄傳）　代號 `guojing`

隊友・攻擊；成名絕技 「降龍十八掌」、「雙手互搏」。

```
金庸武俠人物：郭靖（射鵰英雄傳，江南七怪／洪七公傳人）。二十多歲壯實青年，濃眉大眼、膚色黝黑，土黃短打外罩灰褐羊皮背心，腰繫布帶，空手，站姿穩重，神情憨厚。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：弓步向左下方推出右掌，左手護胸，掌前湧出一條盤旋的金色龍形掌勁（降龍十八掌「亢龍有悔」）。`

#### 黃蓉（射鵰英雄傳）　代號 `huangrong`

隊友・控制；成名絕技 「打狗棒法」、「軟蝟甲」。

```
金庸武俠人物：黃蓉（射鵰英雄傳，桃花島／丐幫幫主）。十五六歲嬌俏少女，白衣、綠緞帶、頭束金環，手持一根碧綠竹棒，靈動含笑。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：輕盈地側身，用碧綠竹棒向左下方點出一記「絆」字訣，棒影如綠色殘影纏繞，裙帶飄起。`

#### 洪七公（射鵰英雄傳）　代號 `hongqigong`

首領・攻擊；成名絕技 「降龍十八掌」、「打狗棒法」。

```
金庸武俠人物：洪七公（射鵰英雄傳，丐幫幫主）。五十來歲老乞丐，花白鬍鬚，打滿補丁的百衲衣，背一個朱紅酒葫蘆，右手少一根食指（九指神丐），手提綠竹棒。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：左手提竹棒在身後，右掌向左下方猛推，掌前一條巨大的金色龍形氣勁咆哮而出，酒葫蘆晃起。`

#### 黃藥師（射鵰英雄傳）　代號 `huangyaoshi`

首領・控制；成名絕技 「彈指神通」、「碧海潮生曲」。

```
金庸武俠人物：黃藥師（射鵰英雄傳，桃花島主）。清癯中年文士，一身青色長袍，面色淡漠帶傲氣，手持一支碧玉簫，長鬚飄逸。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：玉簫橫在唇邊，另一手向左下方彈指，一顆石子化成一道細亮光線射出，身周有淡青色音波漣漪（彈指神通、碧海潮生曲）。`

#### 歐陽鋒（射鵰英雄傳）　代號 `ouyangfeng`

首領・毒；成名絕技 「蛤蟆功」、「靈蛇杖法」。

```
金庸武俠人物：歐陽鋒（射鵰英雄傳，白駝山莊主）。高大的中年西域人，高鼻深目，白袍，手持彎頭蛇杖，杖頭雕人頭，杖上纏兩條青蛇。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：雙膝下蹲成蛤蟆之勢，雙掌向左下方齊推，掌前爆出一圈綠白色氣浪，蛇杖斜插身旁、杖上青蛇昂首吐信（蛤蟆功）。`

#### 一燈大師（射鵰英雄傳）　代號 `yideng`

首領・治療；成名絕技 「一陽指」、「先天功」。

```
金庸武俠人物：一燈大師（射鵰英雄傳，大理段氏）。白眉老僧，面容慈和，粗布灰色僧袍，身形清瘦，赤手，左手持念珠。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：側身伸出右手食指向左下方點出，指尖一道溫潤的金色細光（一陽指），左手立掌於胸前。`

#### 楊過（神鵰俠侶）　代號 `yangguo`

隊友・攻擊；成名絕技 「黯然銷魂掌」、「玄鐵重劍」。

```
金庸武俠人物：楊過（神鵰俠侶，古墓派）。二十多歲俊朗青年，右袖空蕩（獨臂），灰青長衫，背一柄黝黑寬大的玄鐵重劍，神情孤傲。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：獨臂單掌向左下方拍出，神情黯然，掌前一團灰藍色悲涼掌勁，空袖向後飄起（黯然銷魂掌）。`

#### 小龍女（神鵰俠侶）　代號 `xiaolongnu`

隊友・速攻；成名絕技 「玉女素心劍法」、「玉蜂針」。

```
金庸武俠人物：小龍女（神鵰俠侶，古墓派掌門）。十八九歲絕美少女，肌膚勝雪，一身純白衣裙，長髮披肩，神情清冷出塵，手持一柄素劍，腰繫銀索金鈴。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：白衣飄飛，素劍向左下方輕靈刺出，劍光如月華，幾隻小玉蜂繞身飛舞（玉女素心劍法）。`

#### 金輪法王（神鵰俠侶）　代號 `jinlun`

首領・坦；成名絕技 「龍象般若功」、「五輪大轉」。

```
金庸武俠人物：金輪法王（神鵰俠侶，蒙古國師）。高大削瘦的藏僧，紅黃袈裟，光頭，身周懸浮金、銀、銅、鐵、鉛五個不同金屬的圓輪。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：雙手一揮，五個金屬圓輪向左下方旋轉飛出，輪緣帶出火花軌跡，身後浮現淡金色龍象虛影。`

#### 謝遜（倚天屠龍記）　代號 `xiexun`

首領・攻擊；成名絕技 「獅子吼」、「七傷拳」。

```
金庸武俠人物：謝遜（倚天屠龍記，明教金毛獅王）。高大壯漢，一頭金色長髮披散，雙目失明，獸皮袍，手持一柄黝黑沉重的屠龍刀。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：仰頭張口怒吼，一圈圈金色聲浪向左下方擴散，屠龍刀高舉過頭（獅子吼）。`

#### 風清揚（笑傲江湖）　代號 `fengqingyang`

傳說・攻擊；成名絕技 「獨孤九劍・總訣式」。

```
金庸武俠人物：風清揚（笑傲江湖，華山派劍宗前輩）。白鬚白髮的瘦削老者，淡青舊布袍，神情蕭索落寞，背微駝，手持一根細竹枝當劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：隨手以竹枝向左下方一點，竹枝前方綻開九道交錯的淡青劍氣，衣袍無風自動（獨孤九劍）。`

#### 東方不敗（笑傲江湖）　代號 `dongfangbubai`

首領・速攻；成名絕技 「葵花寶典」、「繡花針」。

```
金庸武俠人物：東方不敗（笑傲江湖，日月神教教主）。面容白淨、塗脂抹粉的男子，身穿粉紅繡花衣衫，手拈銀色繡花針與紅線，身形纖細，姿態陰柔。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：身形化成粉紅殘影向左下方閃掠，指間一根繡花針帶著長長的紅線射出，數點銀光（葵花寶典、繡花針）。`

#### 任我行（笑傲江湖）　代號 `renwoxing`

首領・坦；成名絕技 「吸星大法」。

```
金庸武俠人物：任我行（笑傲江湖，日月神教前任教主）。身材高大的長臉老者，黑色長袍，鬚髮黑白相間，久囚鐵牢而面色青白，雙手虯結有力，眼神霸道。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：右掌向左下方張開，掌心形成一個深藍色漩渦，把一縷縷白色內力往掌中吸來（吸星大法）。`

#### 段譽（天龍八部）　代號 `duanyu`

隊友・速攻；成名絕技 「六脈神劍」、「凌波微步」。

```
金庸武俠人物：段譽（天龍八部，大理段氏世子）。十八九歲文弱書生，白色儒衫，面容俊秀天真，空手，腰插一把摺扇。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：腳踏凌波微步、身後拖出淡淡殘影，右手六指齊張向左下方一指，六道細長的淡藍色無形劍氣射出（六脈神劍）。`

#### 慕容復（天龍八部）　代號 `murongfu`

首領・控制；成名絕技 「斗轉星移」、「參合指」。

```
金庸武俠人物：慕容復（天龍八部，姑蘇慕容氏）。二十七八歲俊美公子，月白錦袍，頭戴方巾，手持長劍，氣度高傲。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：長劍斜指，左掌向左下方一引，身前一個銀色星軌旋渦把對方攻勢倒轉回去（斗轉星移）。`

#### 鳩摩智（天龍八部）　代號 `jiumozhi`

首領・攻擊；成名絕技 「火焰刀」、「小無相功」。

```
金庸武俠人物：鳩摩智（天龍八部，吐蕃國師）。五十多歲番僧，光頭，金黃與絳紅僧袍，身形高大，面帶淺笑，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：單掌如刀向左下方斜斬，掌緣噴出一道扇形的赤紅火焰刀氣（火焰刀）。`

### 13.2 批次 B：第二批（20 位）

其餘常見的首領與名人。

#### 周伯通（射鵰英雄傳）　代號 `zhoubotong`

隊友・速攻；成名絕技 「空明拳」、「雙手互搏」。

```
金庸武俠人物：周伯通（射鵰英雄傳，全真教）。鬚髮皆白的頑童老頭，笑嘻嘻，灰白道袍敞開、腰帶亂綁，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：雙手各打出一拳，左右手招式不同（一拳一掌），向左下方同時出擊，咧嘴大笑（雙手互搏、空明拳）。`

#### 王重陽（射鵰英雄傳）　代號 `wangchongyang`

傳說・攻擊；成名絕技 「先天功」、「一陽指」。

```
金庸武俠人物：王重陽（射鵰英雄傳，全真教祖師）。五十來歲道人，長鬚三綹，白底藍邊道袍，背一柄古劍，仙風道骨。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：一手捏道訣在胸前，一手向左下方點出，身周升起一圈白金色的先天罡氣。`

#### 梅超風（射鵰英雄傳）　代號 `meichaofeng`

精英・攻擊；成名絕技 「九陰白骨爪」、「白蟒鞭」。

```
金庸武俠人物：梅超風（射鵰英雄傳，桃花島叛徒）。中年女子，雙目失明，長髮披散，黑衣，腰纏銀白長鞭，十指尖長泛青。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：長髮飛揚，五指成鉤向左下方抓下，指尖拖出五道青白色爪痕（九陰白骨爪）。`

#### 裘千仞（射鵰英雄傳）　代號 `qiuqianren`

首領・攻擊；成名絕技 「鐵掌」、「鐵掌水上飄」。

```
金庸武俠人物：裘千仞（射鵰英雄傳，鐵掌幫幫主）。六十來歲老者，白鬚，黃葛短衫，手持蒲扇，雙掌粗厚泛著鐵色。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：扔開蒲扇，單掌向左下方重重劈出，手掌泛出黑鐵色光澤，掌風捲起塵土（鐵掌）。`

#### 公孫止（神鵰俠侶）　代號 `gongsunzhi`

首領・攻擊；成名絕技 「陰陽倒亂刃法」、「閉穴功」。

```
金庸武俠人物：公孫止（神鵰俠侶，絕情谷谷主）。四五十歲清瘦男子，面目冷峻，淡綠長袍，左手一柄金刀、右手一柄黑劍，眼神陰冷。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：左手金刀向左下方劈落、右手黑劍同時刺出，金黑兩道光弧交錯（陰陽倒亂刃法）。`

#### 周芷若（倚天屠龍記）　代號 `zhouzhiruo`

首領・攻擊；成名絕技 「九陰白骨爪」、「白蟒鞭」。

```
金庸武俠人物：周芷若（倚天屠龍記，峨嵋派掌門）。二十歲清麗女子，柳眉，淡青峨嵋掌門道袍，長髮，手執一條銀白長鞭，眼神帶點陰鬱。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：銀白長鞭在身側翻捲，另一手五指成爪向左下方抓出，指尖拖出青白色爪痕（九陰白骨爪）。`

#### 殷天正（倚天屠龍記）　代號 `yintianzheng`

首領・攻擊；成名絕技 「鷹爪擒拿手」。

```
金庸武俠人物：殷天正（倚天屠龍記，明教白眉鷹王）。七旬老者，兩道長長的白眉垂到臉頰，白袍，十指如鷹爪。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：身形如鷹撲下，雙手成鷹爪向左下方抓去，白眉與衣袖翻飛，爪前有金色爪影。`

#### 韋一笑（倚天屠龍記）　代號 `weiyixiao`

精英・速攻；成名絕技 「寒冰綿掌」、「青翼蝠王輕功」。

```
金庸武俠人物：韋一笑（倚天屠龍記，明教青翼蝠王）。瘦削的中年男子，青白臉色，披一件像蝙蝠翅膀的青色大披風，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：青色披風如蝠翼張開，身形斜掠向左下方，一掌拍出，掌上凝著白霜寒氣（寒冰綿掌）。`

#### 成昆（倚天屠龍記）　代號 `chengkun`

首領・控制；成名絕技 「幻陰指」、「混元霹靂手」。

```
金庸武俠人物：成昆（倚天屠龍記，少林）。六十來歲瘦削老僧，灰黃袈裟，面容陰沉，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：一手陰沉地點出幻陰指，另一掌向左下方劈出，掌心迸出紫白色雷光（混元霹靂手）。`

#### 楊逍（倚天屠龍記）　代號 `yangxiao`

首領・攻擊；成名絕技 「乾坤大挪移（第二層）」、「彈指神通」。

```
金庸武俠人物：楊逍（倚天屠龍記，明教光明左使）。四十來歲瀟灑男子，青衫長袍，冷傲英俊，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：身形瀟灑一轉，右掌向左下方推出，掌前一道旋轉的乾坤氣旋把攻勢反卷回去（乾坤大挪移）。`

#### 任盈盈（笑傲江湖）　代號 `renyingying`

隊友・治療；成名絕技 「清心普善咒」、「笑傲江湖曲」。

```
金庸武俠人物：任盈盈（笑傲江湖，日月神教聖姑）。十七八歲清麗少女，素淨綠衣，烏黑長髮，懷抱一張古琴，腰插短劍，氣質冷傲。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：盤坐撫琴，十指撥弦，一圈圈淡綠色的音波與音符向左下方飄散（清心普善咒）。`

#### 林平之（笑傲江湖）　代號 `linpingzhi`

首領・速攻；成名絕技 「辟邪劍法」。

```
金庸武俠人物：林平之（笑傲江湖，福威鏢局少主／華山派）。二十歲左右俊美青年，臉色蒼白近乎陰柔，一身黑衣，手持細長劍，眼神陰冷。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：身形快得只剩黑影，細劍向左下方連刺，劍尖化成數道交錯的紅白光點（辟邪劍法）。`

#### 田伯光（笑傲江湖）　代號 `tianboguang`

精英・速攻；成名絕技 「快刀」、「萬里獨行」。

```
金庸武俠人物：田伯光（笑傲江湖，萬里獨行）。三十多歲精悍漢子，黑色短打勁裝，敞著胸，單刀在手，嘴角帶痞笑。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：單刀連斬兩記，在左下方劃出兩道交叉的快速刀光，身形微微模糊（快刀）。`

#### 左冷禪（笑傲江湖）　代號 `zuolengchan`

首領・控制；成名絕技 「寒冰真氣」、「嵩山劍法」。

```
金庸武俠人物：左冷禪（笑傲江湖，嵩山派掌門／五嶽劍派盟主）。五十多歲高大男子，臉色青白，杏黃色嵩山派長袍，腰懸長劍，神情倨傲陰沉。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：一掌向左下方推出，掌心噴出白色寒霧，空氣中凝起冰晶（寒冰真氣），另一手按著劍柄。`

#### 李秋水（天龍八部）　代號 `liqiushui`

首領・控制；成名絕技 「白虹掌力」、「小無相功」。

```
金庸武俠人物：李秋水（天龍八部，逍遙派）。白紗蒙面的美貌婦人，白衣飄飄，紗下隱約可見臉上的井字劍痕，姿態輕盈。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：衣袖一揮，一道白色長虹般的掌力向左下方彎曲射出（白虹掌力）。`

#### 掃地僧（天龍八部）　代號 `saodiseng`

傳說・輔助；成名絕技 「一掌假死」。

```
金庸武俠人物：掃地僧（天龍八部，少林寺藏經閣）。枯瘦年邁的灰衣老僧，手持竹掃帚，鬍鬚稀疏，神情平和。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：竹掃帚輕輕倚在身旁，單掌平平向左下方推出，掌前一圈柔和的金色佛光漣漪。`

#### 段延慶（天龍八部）　代號 `duanyanqing`

首領・控制；成名絕技 「一陽指（鋼杖）」、「腹語術」。

```
金庸武俠人物：段延慶（天龍八部，四大惡人之首）。面容僵硬如殭屍的殘疾人，青袍，雙手各拄一根細鋼杖代步，嘴唇不動。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：單杖撐地，另一根鋼杖向左下方點出，杖尖射出一道金色指勁（一陽指）。`

#### 袁承志（碧血劍）　代號 `yuanchengzhi`

傳說・攻擊；成名絕技 「金蛇劍法」、「混元功」。

```
金庸武俠人物：袁承志（碧血劍，華山派，袁崇煥之子）。二十歲左右的青年，藍布長衫，手持一柄金色蛇形彎劍，面容堅毅。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：金蛇劍向左下方蜿蜒刺出，劍光扭成一條金色蛇形（金蛇劍法）。`

#### 狄雲（連城訣）　代號 `diyun`

隊友・坦；成名絕技 「神照經」、「血刀刀法」。

```
金庸武俠人物：狄雲（連城訣，戚長發弟子）。二十多歲的樸實青年，面容憔悴，破舊粗布衣外披一件紅色僧袍，手持一柄血紅的彎刀。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：彎刀向左下方斜劈，刀光血紅；身周泛起一圈淡白色的神照經護體光。`

#### 石破天（俠客行）　代號 `shipotian`

傳說・坦；成名絕技 「太玄經」、「金烏刀法」。

```
金庸武俠人物：石破天（俠客行，長樂幫幫主／金烏派大弟子）。二十歲的憨厚青年，衣著樸素，臉上滿是笑容，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：憨笑著隨手向左下方一推，身後浮現石壁上蝌蚪文般的金色字跡，一股渾厚氣勁湧出（太玄經）。`

### 13.3 批次 C：其餘人物（140 位）

依級別排序（傳說、首領在前，精英、隊友在後）。

#### 黃衫女子（倚天屠龍記）　代號 `huangshannv`

傳說・暗器；成名絕技 「九陰真經」、「打狗棒法」。

```
金庸武俠人物：黃衫女子（倚天屠龍記，古墓派傳人）。二十多歲清麗女子，淡黃衫子，神情冷峻，手持一根竹棒。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：竹棒向左下方點出，棒影如游龍，衣帶飄起，身周一縷淡金色真氣。`

#### 方證大師（笑傲江湖）　代號 `fangzheng`

傳說・坦；成名絕技 「千手如來掌」、「易筋經」。

```
金庸武俠人物：方證大師（笑傲江湖，少林寺方丈）。白眉白鬚的高齡老僧，黃色僧袍披紅色袈裟，面容慈祥。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：雙掌連拍，身後浮現無數金色掌影如千手觀音，向左下方湧出（千手如來掌）。`

#### 無崖子（天龍八部）　代號 `wuyazi`

傳說・輔助；成名絕技 「北冥神功・傳功」。

```
金庸武俠人物：無崖子（天龍八部，逍遙派掌門）。鬚髮如銀的俊美老者，身穿白袍，雙腿不能動，被一條黑索懸吊在半空，神情溫和。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：懸在半空，雙掌向左下方推出，一道浩瀚的藍白色真氣如海潮般湧出（北冥神功）。`

#### 九難（鹿鼎記）　代號 `jiunan`

傳說・速攻；成名絕技 「神行百變」、「鐵劍門劍法」。

```
金庸武俠人物：九難（鹿鼎記，長平公主）。中年尼姑，左袖空蕩（獨臂），容貌清麗但神情冷峻，灰色僧袍，右手持劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：獨臂持劍化成三道殘影向左下方連刺。`

#### 袁士霄（書劍恩仇錄）　代號 `yuanshixiao`

傳說・攻擊；成名絕技 「百花錯拳（原創）」。

```
金庸武俠人物：袁士霄（書劍恩仇錄，天池怪俠）。七十多歲的瘦小怪老頭，白髮蓬亂，破舊灰袍，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方衝拳或五指成爪抓出，身體前衝，拳爪前帶出氣勁（表現「百花錯拳（原創）」）。`

#### 夏雪宜（碧血劍）　代號 `xiaxueyi`

傳說・暗器；成名絕技 「金蛇劍」、「金蛇錐」。

```
金庸武俠人物：夏雪宜（碧血劍，金蛇郎君）。三十歲的俊美邪氣男子，黑色長袍，袍角繡著金蛇，手持金蛇劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「金蛇劍」）。`

#### 穆人清（碧血劍）　代號 `murenqing`

傳說・攻擊；成名絕技 「華山劍法」。

```
金庸武俠人物：穆人清（碧血劍，華山派掌門）。七十歲的老者，白鬚，青布長袍，背負長劍，精神矍鑠。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「華山劍法」）。`

#### 木桑道人（碧血劍）　代號 `musang`

傳說・暗器；成名絕技 「鐵劍門暗器手法」、「神行百變」。

```
金庸武俠人物：木桑道人（碧血劍，鐵劍門掌門）。六十歲的胖道士，褪色黃道袍，袖中藏著棋子，一副嬉笑模樣。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：兩袖一抖，滿天暗器與棋子向左下方灑出。`

#### 胡一刀（雪山飛狐／飛狐外傳）　代號 `huyidao`

傳說・攻擊；成名絕技 「胡家刀法（原創）」。

```
金庸武俠人物：胡一刀（雪山飛狐／飛狐外傳，遼東大俠）。三十多歲的魁梧大漢，滿臉虯髯，獸皮大衣，手持厚背單刀。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：揮刀向左下方斜劈，刀身拖出一道寒光弧線（表現「胡家刀法（原創）」）。`

#### 張三李四（俠客行）　代號 `zhangsanlisi`

傳說・攻擊；成名絕技 「賞善罰惡」。

```
金庸武俠人物：張三李四（俠客行，俠客島賞善罰惡使者）。兩個五十歲的人站在一起（畫在同一張圖裡）：張三胖臉笑嘻嘻，李四瘦臉陰沉，都穿深藍袍，各持一面銅牌。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：兩人一左一右同時向左下方出掌，一掌金色、一掌銅色。`

#### 蕭半和（鴛鴦刀）　代號 `xiaobanhe`

傳說・坦；成名絕技 「渾元氣功」。

```
金庸武俠人物：蕭半和（鴛鴦刀，晉陽大俠蕭義）。五十歲的白淨中年人，沒有鬍鬚，棕色員外袍，空手，神情溫和。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：雙掌在胸前運氣後向左下方推出，全身有淡青色內力氣旋環繞（表現「渾元氣功」）。`

#### 阿青（越女劍）　代號 `aqing`

傳說・攻擊；成名絕技 「越女劍法」。

```
金庸武俠人物：阿青（越女劍，越國牧羊少女）。十五歲的牧羊少女，淡綠粗布衣，赤足，手持一根細竹棒，身邊一隻小白羊。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：竹棒向左下方輕輕一點，竹梢前綻開一道極細極亮的劍光，衣帶揚起。`

#### 黛綺絲（金花婆婆）（倚天屠龍記）　代號 `daiqisi`

首領・暗器；成名絕技 「金花」。

```
金庸武俠人物：黛綺絲（金花婆婆）（倚天屠龍記，明教紫衫龍王）。佝僂老婦拄著拐杖，灰布衣，但手中拈著幾朵閃亮的金花。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：拐杖拄地，手腕一抖，三朵金花分三路旋轉射向左下方。`

#### 少林三渡（倚天屠龍記）　代號 `sandu`

首領・坦；成名絕技 「金剛伏魔圈」。

```
金庸武俠人物：少林三渡（倚天屠龍記，少林寺）。三位枯槁老僧並排盤坐（畫在同一張圖裡），黑色僧袍，各持一根長黑索，居中的渡厄一眼已眇。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：三人同時甩出三條黑索，在左下方交織成一個大圓圈（金剛伏魔圈）。`

#### 蕭遠山（天龍八部）　代號 `xiaoyuanshan`

首領・攻擊；成名絕技 「少林七十二絕技（偷學）」。

```
金庸武俠人物：蕭遠山（天龍八部，契丹武士）。高大的黑衣蒙面僧人，黑布袍，身形魁梧，鬚髮斑白。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：黑袍翻飛，一掌一拳向左下方齊出，身周浮現多種少林絕技的金色虛影。`

#### 慕容博（天龍八部）　代號 `murongbo`

首領・控制；成名絕技 「參合指」、「斗轉星移」。

```
金庸武俠人物：慕容博（天龍八部，姑蘇慕容氏）。灰衣蒙面的中年人，灰色僧袍，神情深沉。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：側身向左下方伸指點出，指尖射出一道細長的亮光（表現「參合指」）。`

#### 陳近南（鹿鼎記）　代號 `chenjinnan`

首領・攻擊；成名絕技 「凝血神爪」。

```
金庸武俠人物：陳近南（鹿鼎記，天地會總舵主）。四十多歲儒雅書生，臉色清癯，三綹長鬚，青布長衫，空手，氣度沉穩。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：五指成爪向左下方抓出，爪前一團暗紅色的血氣凝結（凝血神爪）。`

#### 洪安通（鹿鼎記）　代號 `honganton`

首領・控制；成名絕技 「英雄三招」。

```
金庸武俠人物：洪安通（鹿鼎記，神龍教教主）。六十歲左右的魁梧老者，白鬚，金黃色長袍，空手，神情倨傲。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：雙手抓起一個無形的對手向左下方摔出（英雄三招），身後有金色神龍虛影。`

#### 鰲拜（鹿鼎記）　代號 `aobai`

首領・坦；成名絕技 「滿洲第一勇士」。

```
金庸武俠人物：鰲拜（鹿鼎記，清廷輔政大臣）。高大魁梧的滿洲大漢，滿臉橫肉，深藍朝服、戴頂戴，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：怒目圓睜，揮起巨拳向左下方猛砸，朝服撐裂。`

#### 張召重（書劍恩仇錄）　代號 `zhangzhaozhong`

首領・攻擊；成名絕技 「柔雲劍術・凝碧劍」。

```
金庸武俠人物：張召重（書劍恩仇錄，清廷御前侍衛）。四十多歲的威猛男子，大內侍衛官服，手持一柄碧綠寶劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：凝碧劍向左下方重重斬落，劍身拖出碧綠色光弧。`

#### 溫氏五老（碧血劍）　代號 `wenshiwulao`

首領・控制；成名絕技 「五行陣」。

```
金庸武俠人物：溫氏五老（碧血劍，石樑溫家）。五個六十歲上下的老者（畫在同一張圖裡），分別穿青、赤、黃、白、黑五色長袍，各拿不同兵器。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：五人錯落站位，同時向左下方出手，地面亮起五色五行陣紋。`

#### 玉真子（碧血劍）　代號 `yuzhenzi`

首領・攻擊；成名絕技 「鐵劍門劍法」。

```
金庸武俠人物：玉真子（碧血劍，鐵劍門叛徒）。四十歲的淫邪道士，華麗紫袍，手持鐵劍，目光不正。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「鐵劍門劍法」）。`

#### 苗人鳳（雪山飛狐／飛狐外傳）　代號 `miaorenfeng`

首領・攻擊；成名絕技 「苗家劍法」。

```
金庸武俠人物：苗人鳳（雪山飛狐／飛狐外傳，打遍天下無敵手）。四五十歲高大男子，黃臉，面目黃瘦，破舊黃袍，背負長劍，神色落寞。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「苗家劍法」）。`

#### 石萬嗔（雪山飛狐／飛狐外傳）　代號 `shiwanchen`

首領・毒；成名絕技 「毒手神梟毒」。

```
金庸武俠人物：石萬嗔（雪山飛狐／飛狐外傳，毒手神梟）。六十歲的瞎眼老者，黑袍，指甲泛綠，神情陰毒。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方揚手撒出一團綠色毒霧（表現「毒手神梟毒」）。`

#### 落花流水（南四奇）（連城訣）　代號 `luohualiushui`

首領・控制；成名絕技 「落花流水」。

```
金庸武俠人物：落花流水（南四奇）（連城訣，陸天抒、花鐵幹、劉乘風、水岱）。四個中年武師（畫在同一張圖裡）：陸天抒持大刀、花鐵幹持短槍、劉乘風和水岱持劍，都披灰色斗篷。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：四人刀槍劍劍同時向左下方遞出，兵器光芒交錯。`

#### 凌退思（連城訣）　代號 `lingtuisi`

首領・毒；成名絕技 「金波旬花」。

```
金庸武俠人物：凌退思（連城訣，荊州知府）。五十歲的官員，深紅官袍，臉色陰沉，手持一朵金色小花。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方揚手撒出一團綠色毒霧（表現「金波旬花」）。`

#### 謝煙客（俠客行）　代號 `xieyanke`

首領・控制；成名絕技 「碧針清掌」。

```
金庸武俠人物：謝煙客（俠客行，摩天居士）。五十歲的灑脫青袍人，臉色青白，袖風颯颯。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：一掌拍出，無數青綠色松針隨掌風向左下方激射。`

#### 白自在（俠客行）　代號 `baizizai`

首領・攻擊；成名絕技 「雪山劍法」。

```
金庸武俠人物：白自在（俠客行，雪山派掌門）。七十歲的威嚴老者，白髯，白色裘衣，手持長劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「雪山劍法」）。`

#### 瓦耳拉齊（白馬嘯西風）　代號 `waerlaqi`

首領・毒；成名絕技 「毒針」。

```
金庸武俠人物：瓦耳拉齊（白馬嘯西風，哈薩克第一勇士）。六十歲的老者，臉上傷疤密布，哈薩克族黑袍，手藏毒針。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方揚手射出暗器，數點寒光飛出（表現「毒針」）。`

#### 陳玄風（射鵰英雄傳）　代號 `chenxuanfeng`

精英・坦；成名絕技 「橫練功夫」、「九陰白骨爪」。

```
金庸武俠人物：陳玄風（射鵰英雄傳，桃花島叛徒）。高大黑瘦中年漢子，面如古銅，黑衣，空手，十指如鉤。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：雙掌在胸前運氣後向左下方推出，全身有淡青色內力氣旋環繞（表現「橫練功夫」）。`

#### 歐陽克（射鵰英雄傳）　代號 `ouyangke`

精英・控制；成名絕技 「神駝雪山掌」、「蛇陣」。

```
金庸武俠人物：歐陽克（射鵰英雄傳，白駝山少主）。二十多歲俊美公子，白衣，手搖摺扇，神情輕佻。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：弓步向左下方全力推出一掌，身體前傾，掌前湧出一團掌勁（表現「神駝雪山掌」）。`

#### 楊康（射鵰英雄傳）　代號 `yangkang`

精英・攻擊；成名絕技 「九陰白骨爪」、「全真劍法」。

```
金庸武俠人物：楊康（射鵰英雄傳，全真教）。二十歲俊秀貴公子，錦袍玉帶，金冠，手持長劍，神色高傲。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方衝拳或五指成爪抓出，身體前衝，拳爪前帶出氣勁（表現「九陰白骨爪」）。`

#### 靈智上人（射鵰英雄傳）　代號 `lingzhi`

精英・坦；成名絕技 「大手印」。

```
金庸武俠人物：靈智上人（射鵰英雄傳，西藏密宗）。高大的紅袍番僧，光頭，胸掛一串大念珠，雙掌巨大。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：弓步向左下方全力推出一掌，身體前傾，掌前湧出一團掌勁（表現「大手印」）。`

#### 瑛姑（射鵰英雄傳）　代號 `yinggu`

精英・速攻；成名絕技 「泥鰍功」。

```
金庸武俠人物：瑛姑（射鵰英雄傳，大理段氏舊妃）。四十多歲女子，滿頭白髮但面容尚美，灰布衣裙，袖中露出算籌，神情悽苦。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：身形一晃向左下方疾衝，衣袂翻飛，身後拖著淡淡殘影（表現「泥鰍功」）。`

#### 郭芙（神鵰俠侶）　代號 `guofu`

精英・攻擊；成名絕技 「淑女劍」。

```
金庸武俠人物：郭芙（神鵰俠侶，郭靖長女）。二十歲明豔少女，粉紅錦衣，持長劍，神情驕縱。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「淑女劍」）。`

#### 裘千尺（神鵰俠侶）　代號 `qiuqianchi`

精英・暗器；成名絕技 「棗核釘」。

```
金庸武俠人物：裘千尺（神鵰俠侶，鐵掌幫）。禿頭老婦，四肢殘廢，盤坐在一張舊竹椅上，衣衫襤褸，面容怨毒。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：坐在椅上猛一仰頭，口中向左下方噴出一顆棗核，化成一道疾速的褐色光點。`

#### 樊一翁（神鵰俠侶）　代號 `fanyiweng`

精英・坦；成名絕技 「鋼杖長鬚」。

```
金庸武俠人物：樊一翁（神鵰俠侶，絕情谷大弟子）。矮小老者，白色長鬚拖地，綠袍，手持粗鋼杖。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：猛一甩頭，長長的白鬚像鞭子般向左下方甩出，同時鋼杖砸下。`

#### 達爾巴（神鵰俠侶）　代號 `daerba`

精英・坦；成名絕技 「金剛杵」。

```
金庸武俠人物：達爾巴（神鵰俠侶，金輪法王大弟子）。魁梧的藏僧，紅袍，雙手握一根巨大的黃金金剛杵。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：掄起手中兵器向左下方橫掃，帶起風聲與塵土（表現「金剛杵」）。`

#### 霍都（神鵰俠侶）　代號 `huodu`

精英・暗器；成名絕技 「摺扇毒釘」。

```
金庸武俠人物：霍都（神鵰俠侶，蒙古王子）。青年貴公子，白袍，手搖鐵骨摺扇，笑容陰鷙。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：摺扇一張，扇骨間射出數枚毒釘飛向左下方。`

#### 瀟湘子（神鵰俠侶）　代號 `xiaoxiangzi`

精英・毒；成名絕技 「哭喪棒」。

```
金庸武俠人物：瀟湘子（神鵰俠侶，湘西）。高瘦如殭屍的怪人，青白臉色，黑袍，手持哭喪棒。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：掄起手中兵器向左下方橫掃，帶起風聲與塵土（表現「哭喪棒」）。`

#### 尼摩星（神鵰俠侶）　代號 `nimoxing`

精英・攻擊；成名絕技 「鐵蛇」。

```
金庸武俠人物：尼摩星（神鵰俠侶，天竺）。黝黑矮壯的天竺人，頭纏布巾，赤膊，手持一條彎曲的鐵蛇兵刃。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方甩出手中的鞭索，鞭身在空中彎成 S 形（表現「鐵蛇」）。`

#### 尹克西（神鵰俠侶）　代號 `yinkexi`

精英・控制；成名絕技 「金龍鞭」。

```
金庸武俠人物：尹克西（神鵰俠侶，波斯胡商）。中年胡商，高鼻捲鬚，華麗錦袍，手持一條綴滿寶石的金龍長鞭。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方甩出手中的鞭索，鞭身在空中彎成 S 形（表現「金龍鞭」）。`

#### 武三通（神鵰俠侶）　代號 `wusantong`

精英・攻擊；成名絕技 「一陽指」。

```
金庸武俠人物：武三通（神鵰俠侶，一燈大師弟子）。五十來歲狂漢，亂髮虯髯，破舊衣衫，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：側身向左下方伸指點出，指尖射出一道細長的亮光（表現「一陽指」）。`

#### 尹志平（神鵰俠侶）　代號 `yinzhiping`

精英・攻擊；成名絕技 「全真劍法」。

```
金庸武俠人物：尹志平（神鵰俠侶，全真教三代弟子）。青年道士，藍色道袍，手持長劍，神色愧疚。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「全真劍法」）。`

#### 趙志敬（神鵰俠侶）　代號 `zhaozhijing`

精英・攻擊；成名絕技 「全真劍法・欺弱」。

```
金庸武俠人物：趙志敬（神鵰俠侶，全真教三代弟子）。中年道士，藍色道袍，手持長劍，神情刻薄。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「全真劍法・欺弱」）。`

#### 范遙（倚天屠龍記）　代號 `fanyao`

精英・暗器；成名絕技 「苦頭陀」。

```
金庸武俠人物：范遙（倚天屠龍記，明教光明右使）。高大醜陋的頭陀，滿臉刀疤，長髮披肩，灰黑僧衣，不說話，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：一言不發，從偽裝中暴起，雙掌向左下方猛擊。`

#### 殷離（倚天屠龍記）　代號 `yinli`

精英・毒；成名絕技 「千蛛萬毒手」。

```
金庸武俠人物：殷離（倚天屠龍記，金花婆婆弟子）。少女，臉上有黑腫毒斑，粗布裙，十指黑紫，掌心趴著一隻小毒蛛。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方揚手撒出一團綠色毒霧（表現「千蛛萬毒手」）。`

#### 鹿杖客（倚天屠龍記）　代號 `luzhangke`

精英・毒；成名絕技 「玄冥神掌」。

```
金庸武俠人物：鹿杖客（倚天屠龍記，汝陽王府）。禿頂老者，灰白長鬚，手持鹿角杖，掌心泛著青黑寒氣。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：弓步向左下方全力推出一掌，身體前傾，掌前湧出一團掌勁（表現「玄冥神掌」）。`

#### 鶴筆翁（倚天屠龍記）　代號 `hebiweng`

精英・毒；成名絕技 「玄冥神掌」。

```
金庸武俠人物：鶴筆翁（倚天屠龍記，汝陽王府）。黑髮老者，鷹鉤鼻，手持鶴嘴筆，掌心泛著青黑寒氣。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：弓步向左下方全力推出一掌，身體前傾，掌前湧出一團掌勁（表現「玄冥神掌」）。`

#### 王難姑（倚天屠龍記）　代號 `wangnangu`

精英・毒；成名絕技 「毒經」。

```
金庸武俠人物：王難姑（倚天屠龍記，明教）。中年婦人，深綠衣裙，腰掛幾個毒囊，神情倔強。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方揚手撒出一團綠色毒霧（表現「毒經」）。`

#### 何太沖（倚天屠龍記）　代號 `hetaichong`

精英・攻擊；成名絕技 「正兩儀劍法」。

```
金庸武俠人物：何太沖（倚天屠龍記，崑崙派掌門）。中年儒雅男子，黃衫，手持長劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「正兩儀劍法」）。`

#### 宋青書（倚天屠龍記）　代號 `songqingshu`

精英・攻擊；成名絕技 「九陰神爪」。

```
金庸武俠人物：宋青書（倚天屠龍記，武當叛徒）。二十多歲英俊青年，青色勁裝，腰佩長劍，眼神陰鬱。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方衝拳或五指成爪抓出，身體前衝，拳爪前帶出氣勁（表現「九陰神爪」）。`

#### 阿三（倚天屠龍記）　代號 `asan`

精英・攻擊；成名絕技 「大力金剛指」。

```
金庸武俠人物：阿三（倚天屠龍記，金剛門）。矮壯禿頭番僧，赤膊，十指粗大如鐵。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：側身向左下方伸指點出，指尖射出一道細長的亮光（表現「大力金剛指」）。`

#### 余滄海（笑傲江湖）　代號 `yucanghai`

精英・攻擊；成名絕技 「摧心掌」。

```
金庸武俠人物：余滄海（笑傲江湖，青城派掌門）。矮小瘦削的道人，青色道袍，面目陰狠，腰佩長劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：弓步向左下方全力推出一掌，身體前傾，掌前湧出一團掌勁（表現「摧心掌」）。`

#### 木高峰（笑傲江湖）　代號 `mugaofeng`

精英・攻擊；成名絕技 「駝劍」。

```
金庸武俠人物：木高峰（笑傲江湖，塞北明駝）。駝背老者，滿臉肉瘤，粗布黃衣，手持彎曲的駝劍，相貌醜陋。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「駝劍」）。`

#### 黃鍾公（笑傲江湖）　代號 `huangzhonggong`

精英・控制；成名絕技 「七弦無形劍」。

```
金庸武俠人物：黃鍾公（笑傲江湖，西湖梅莊）。枯槁老者，舊褐長袍，懷抱焦尾瑤琴，神情淡泊。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：撥動琴弦，七道無形的淡藍色劍氣從琴弦上向左下方射出。`

#### 黑白子（笑傲江湖）　代號 `heibaizi`

精英・控制；成名絕技 「玄天指」。

```
金庸武俠人物：黑白子（笑傲江湖，西湖梅莊）。臉色極白、頭髮極黑的瘦高中年人，黑白相間的長袍，手拈一枚圍棋子。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：側身向左下方伸指點出，指尖射出一道細長的亮光（表現「玄天指」）。`

#### 禿筆翁（笑傲江湖）　代號 `tubiweng`

精英・攻擊；成名絕技 「裴將軍詩筆法」。

```
金庸武俠人物：禿筆翁（笑傲江湖，西湖梅莊）。矮胖老者，頭禿，長袍墨跡斑斑，手持一支大判官筆。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：判官筆向左下方疾書，空中留下一串墨色大字筆勢。`

#### 丹青生（笑傲江湖）　代號 `danqingsheng`

精英・攻擊；成名絕技 「潑墨披麻劍法」。

```
金庸武俠人物：丹青生（笑傲江湖，西湖梅莊）。滿臉紅光的酒鬼老者，長袍沾著顏料與酒漬，一手持劍、一手抱酒罈。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「潑墨披麻劍法」）。`

#### 封不平（笑傲江湖）　代號 `fengbuping`

精英・攻擊；成名絕技 「狂風快劍」。

```
金庸武俠人物：封不平（笑傲江湖，華山派劍宗）。中年劍客，黃臉，灰色勁裝，長劍出鞘。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「狂風快劍」）。`

#### 雲中鶴（天龍八部）　代號 `yunzhonghe`

精英・速攻；成名絕技 「鋼爪」。

```
金庸武俠人物：雲中鶴（天龍八部，四大惡人之四）。身形細長如竹竿的瘦漢，灰衣，臉頰凹陷，雙手戴著鋼爪。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：細長的身子騰空，雙手鋼爪向左下方連抓，留下兩道銀色爪痕。`

#### 游坦之（天龍八部）　代號 `youtanzhi`

精英・毒；成名絕技 「冰蠶寒毒」。

```
金庸武俠人物：游坦之（天龍八部，聚賢莊少莊主）。戴著鐵面具的青年，衣衫破爛，手腳冰冷發青，形容狼狽。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：弓步向左下方全力推出一掌，身體前傾，掌前湧出一團掌勁（表現「冰蠶寒毒」）。`

#### 摘星子（天龍八部）　代號 `zhaixingzi`

精英・毒；成名絕技 「火燄毒功」。

```
金庸武俠人物：摘星子（天龍八部，星宿派大弟子）。三十多歲瘦削男子，星宿派灰綠道袍，手中燃著幽綠色毒火。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：雙掌一推，一團幽綠色毒火向左下方噴出。`

#### 海大富（鹿鼎記）　代號 `haidafu`

精英・毒；成名絕技 「化骨綿掌」。

```
金庸武俠人物：海大富（鹿鼎記，清宮太監）。病懨懨的老太監，臉色蠟黃，雙眼已盲，佝僂，灰藍色太監服，空手，常咳嗽。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：弓步向左下方全力推出一掌，身體前傾，掌前湧出一團掌勁（表現「化骨綿掌」）。`

#### 馮錫範（鹿鼎記）　代號 `fengxifan`

精英・攻擊；成名絕技 「一劍無血」。

```
金庸武俠人物：馮錫範（鹿鼎記，台灣延平王府）。五十歲左右的高瘦男子，臉色陰沉，深紫錦袍，手持細長劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「一劍無血」）。`

#### 白振（書劍恩仇錄）　代號 `baizhen`

精英・控制；成名絕技 「大力鷹爪功」。

```
金庸武俠人物：白振（書劍恩仇錄，清廷大內侍衛）。五十歲的鷹鼻侍衛，黃馬褂，手指粗大如鉤。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：側身向左下方伸指點出，指尖射出一道細長的亮光（表現「大力鷹爪功」）。`

#### 何鐵手（碧血劍）　代號 `hetieshou`

精英・毒；成名絕技 「鐵蜈鉤」、「含沙射影」。

```
金庸武俠人物：何鐵手（碧血劍，五毒教教主）。二十多歲的妖豔女子，五彩苗服，赤足戴金環，左手是一隻鐵鉤。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方揚手撒出一團綠色毒霧（表現「鐵蜈鉤」）。`

#### 歸辛樹（碧血劍）　代號 `guixinshu`

精英・攻擊；成名絕技 「劈石破玉拳」。

```
金庸武俠人物：歸辛樹（碧血劍，華山派）。五十歲的矮壯男子，面色木訥，灰色短衣，拳頭極大。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方衝拳或五指成爪抓出，身體前衝，拳爪前帶出氣勁（表現「劈石破玉拳」）。`

#### 田歸農（雪山飛狐／飛狐外傳）　代號 `tianguinong`

精英・攻擊；成名絕技 「天龍劍法」。

```
金庸武俠人物：田歸農（雪山飛狐／飛狐外傳，天龍門北宗掌門）。四十歲的英俊男子，華貴錦袍，手持長劍，神情陰鬱。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「天龍劍法」）。`

#### 鳳天南（雪山飛狐／飛狐外傳）　代號 `fengtiannan`

精英・坦；成名絕技 「黃金棍」。

```
金庸武俠人物：鳳天南（雪山飛狐／飛狐外傳，五虎門掌門）。五十歲的富態惡霸，金線綢袍，手持一根鍍金的長棍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：掄起手中兵器向左下方橫掃，帶起風聲與塵土（表現「黃金棍」）。`

#### 寶象（連城訣）　代號 `baoxiang`

精英・攻擊；成名絕技 「血刀刀法」。

```
金庸武俠人物：寶象（連城訣，血刀門僧人）。四十歲的胖大番僧，血紅色袈裟，手持彎刀。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：揮刀向左下方斜劈，刀身拖出一道寒光弧線（表現「血刀刀法」）。`

#### 萬震山（連城訣）　代號 `wanzhenshan`

精英・攻擊；成名絕技 「連城劍法」。

```
金庸武俠人物：萬震山（連城訣，梅念笙大弟子）。五十歲的富態武人，深褐綢袍，手持長劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「連城劍法」）。`

#### 戚長發（連城訣）　代號 `qichangfa`

精英・控制；成名絕技 「躺屍劍法」。

```
金庸武俠人物：戚長發（連城訣，梅念笙三弟子）。五十歲的鄉下老漢，粗布短衣，手持長劍，目光狡黠。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：身子往後一倒像要摔地，手中長劍卻從下方向左下方陰險地挑出。`

#### 丁不三（俠客行）　代號 `dingbusan`

精英・控制；成名絕技 「一日不過三」。

```
金庸武俠人物：丁不三（俠客行，丁家）。六十歲的瘦削老頭，灰袍，臉上帶著陰笑，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方衝拳或五指成爪抓出，身體前衝，拳爪前帶出氣勁（表現「一日不過三」）。`

#### 丁不四（俠客行）　代號 `dingbusi`

精英・控制；成名絕技 「一日不過四」。

```
金庸武俠人物：丁不四（俠客行，丁家）。六十歲的老頭，褐色長袍，嬉皮笑臉，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方衝拳或五指成爪抓出，身體前衝，拳爪前帶出氣勁（表現「一日不過四」）。`

#### 卓天雄（鴛鴦刀）　代號 `zhuotianxiong`

精英・坦；成名絕技 「震天三十掌」、「呼延十八鞭」。

```
金庸武俠人物：卓天雄（鴛鴦刀，清廷大內侍衛）。五十歲的高大男子，扮成瞎眼乞丐，衣衫襤褸，手持鐵鞭，面目兇悍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：弓步向左下方全力推出一掌，身體前傾，掌前湧出一團掌勁（表現「震天三十掌」）。`

#### 絕情谷綠衣弟子（通用門派弟子）　代號 `g_jueqing`

精英・控制；成名絕技 「漁網陣」。

```
金庸武俠人物：絕情谷綠衣弟子（通用門派弟子，絕情谷）。絕情谷的綠衣弟子，一身淡綠短衣，頭戴綠巾，雙手張開一張大漁網。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：雙手把漁網向左下方撒開，網子在空中張成一個大圓。`

#### 柯鎮惡（射鵰英雄傳）　代號 `kezhene`

隊友・暗器；成名絕技 「毒菱」、「伏魔杖法」。

```
金庸武俠人物：柯鎮惡（射鵰英雄傳，江南七怪之首）。五十多歲瞎眼老者，面目醜陋兇悍，灰黑布衣，手持粗重的烏黑鐵杖，腰掛暗器囊，雙目緊閉。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方揚手射出暗器，數點寒光飛出（表現「毒菱」）。`

#### 穆念慈（射鵰英雄傳）　代號 `munianci`

隊友・速攻；成名絕技 「逍遙遊」。

```
金庸武俠人物：穆念慈（射鵰英雄傳，楊鐵心義女）。十八九歲紅衣少女，眉目清秀，紅衫紅裙，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方衝拳或五指成爪抓出，身體前衝，拳爪前帶出氣勁（表現「逍遙遊」）。`

#### 陸乘風（射鵰英雄傳）　代號 `luchengfeng`

隊友・輔助；成名絕技 「旋風掃葉腿」。

```
金庸武俠人物：陸乘風（射鵰英雄傳，桃花島弟子）。中年儒雅莊主，雙腿殘廢，拄著雙拐，青衫。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：撐著雙拐騰身，一條腿向左下方橫掃，腿風捲起落葉（旋風掃葉腿）。`

#### 哲別（射鵰英雄傳）　代號 `zhebie`

隊友・暗器；成名絕技 「射鵰神箭」。

```
金庸武俠人物：哲別（射鵰英雄傳，蒙古神箭手）。三十多歲蒙古武士，皮帽皮甲，背長弓與箭囊。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：拉滿長弓，箭頭指向左下方，弓弦緊繃，箭尖閃一點寒光（射鵰神箭）。`

#### 馬鈺（射鵰英雄傳）　代號 `mayu`

隊友・輔助；成名絕技 「金雁功」。

```
金庸武俠人物：馬鈺（射鵰英雄傳，全真七子之首）。五十來歲溫和道人，灰色道袍，手持拂塵，面容恬淡。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：身形一晃向左下方疾衝，衣袂翻飛，身後拖著淡淡殘影（表現「金雁功」）。`

#### 王處一（射鵰英雄傳）　代號 `wangchuyi`

隊友・坦；成名絕技 「鐵腳」。

```
金庸武俠人物：王處一（射鵰英雄傳，全真七子）。中年道人，灰藍道袍，背負長劍，神情剛正。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：單足立地，另一腳向左下方高踢而出，腳前一圈氣勁（鐵腳）。`

#### 郭襄（神鵰俠侶）　代號 `guoxiang`

隊友・輔助；成名絕技 「金針三願」、「落英神劍掌」。

```
金庸武俠人物：郭襄（神鵰俠侶，郭靖之女）。十六七歲活潑少女，淡黃衫子，頭繫小髻，腰懸短劍，手捏一枚金針，靈動嬌憨。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方拍出一掌，掌風中飄散著粉色落花瓣，另一手高舉一枚閃光的金針（落英神劍掌、金針）。`

#### 程英（神鵰俠侶）　代號 `chengying`

隊友・治療；成名絕技 「蘭花拂穴手」、「玉簫」。

```
金庸武俠人物：程英（神鵰俠侶，桃花島）。溫婉少女，青衣，素淨面容，手持一支玉簫。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：玉簫在唇邊吹奏，另一手蘭花指向左下方輕拂，一縷淡綠色音波與蘭花虛影飄出。`

#### 公孫綠萼（神鵰俠侶）　代號 `gongsunlve`

隊友・治療；成名絕技 「絕情丹」。

```
金庸武俠人物：公孫綠萼（神鵰俠侶，絕情谷）。十八九歲溫柔少女，淡綠衣裙，鬢邊插一朵情花，雙手捧一個小藥盒。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方遞出藥瓶或丹藥，手上泛出柔和的綠光（表現「絕情丹」）。`

#### 朱子柳（神鵰俠侶）　代號 `zhuziliu`

隊友・控制；成名絕技 「一陽指書法」。

```
金庸武俠人物：朱子柳（神鵰俠侶，一燈大師弟子）。中年書生，青衫方巾，手持一支大號毛筆。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：揮動大毛筆向左下方點出，筆尖拖出一道墨色草書筆跡。`

#### 神鵰（神鵰俠侶）　代號 `shendiao`

隊友・坦；成名絕技 「鵰翅擊」。

```
金庸武俠人物：神鵰（神鵰俠侶，獨孤求敗遺鵰）。巨大醜陋的黑褐色怪鵰，比人還高，頭頂有肉瘤，鉤喙，羽毛稀疏，雙腿粗壯。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：張開兩隻巨翅向左下方猛撲橫掃，捲起一陣狂風與羽毛。`

#### 馮默風（神鵰俠侶）　代號 `fengmofeng`

隊友・坦；成名絕技 「捨身一擊」。

```
金庸武俠人物：馮默風（神鵰俠侶，桃花島弟子）。跛足老鐵匠，皮圍裙，手持大鐵鎚。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：跛足向前撲出，雙手舉鐵鎚向左下方奮力砸下，鎚頭火星四濺。`

#### 耶律齊（神鵰俠侶）　代號 `yeluqi`

隊友・攻擊；成名絕技 「空明拳」。

```
金庸武俠人物：耶律齊（神鵰俠侶，周伯通弟子／丐幫幫主）。二十多歲英挺青年，契丹貴族錦袍，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方衝拳或五指成爪抓出，身體前衝，拳爪前帶出氣勁（表現「空明拳」）。`

#### 小昭（倚天屠龍記）　代號 `xiaozhao`

隊友・輔助；成名絕技 「世情推物理」。

```
金庸武俠人物：小昭（倚天屠龍記，波斯明教聖女）。十五六歲少女，波斯混血的藍色眼眸，丫鬟裝，腳上拖著一段鐵鍊。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：雙手合在胸前輕聲吟唱，一圈圈淡藍色的柔和光環向左下方擴散。`

#### 宋遠橋（倚天屠龍記）　代號 `songyuanqiao`

隊友・輔助；成名絕技 「真武七截陣」。

```
金庸武俠人物：宋遠橋（倚天屠龍記，武當七俠之首）。五十來歲端正道俠，藍灰道袍，手持長劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：長劍向左下方平指，腳下浮現淡金色北斗七星陣紋。`

#### 俞蓮舟（倚天屠龍記）　代號 `yulianzhou`

隊友・坦；成名絕技 「虎爪絕戶手」。

```
金庸武俠人物：俞蓮舟（倚天屠龍記，武當二俠）。四十多歲沉穩道俠，不苟言笑，灰藍短打，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方衝拳或五指成爪抓出，身體前衝，拳爪前帶出氣勁（表現「虎爪絕戶手」）。`

#### 張松溪（倚天屠龍記）　代號 `zhangsongxi`

隊友・控制；成名絕技 「武當綿掌」。

```
金庸武俠人物：張松溪（倚天屠龍記，武當四俠）。四十歲左右精明幹練的道俠，青灰道袍，空手，眼神靈動。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：弓步向左下方全力推出一掌，身體前傾，掌前湧出一團掌勁（表現「武當綿掌」）。`

#### 殷梨亭（倚天屠龍記）　代號 `yinliting`

隊友・速攻；成名絕技 「柔雲劍法」。

```
金庸武俠人物：殷梨亭（倚天屠龍記，武當六俠）。三十多歲清秀道俠，眉帶憂鬱，月白道袍，手持長劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「柔雲劍法」）。`

#### 莫聲谷（倚天屠龍記）　代號 `moshenggu`

隊友・速攻；成名絕技 「繞指柔劍」。

```
金庸武俠人物：莫聲谷（倚天屠龍記，武當七俠）。二十多歲豪爽道俠，青色道袍，手持長劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「繞指柔劍」）。`

#### 張翠山（倚天屠龍記）　代號 `zhangcuishan`

隊友・攻擊；成名絕技 「倚天屠龍功」。

```
金庸武俠人物：張翠山（倚天屠龍記，武當五俠）。二十多歲俊雅書生，白衫，左手爛銀虎頭鉤、右手鑌鐵判官筆。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：鉤筆齊揮，向左下方凌空書寫，留下一串銀色的字形筆勢（倚天屠龍功）。`

#### 殷素素（倚天屠龍記）　代號 `yinsusu`

隊友・暗器；成名絕技 「蚊鬚針」。

```
金庸武俠人物：殷素素（倚天屠龍記，天鷹教）。二十來歲美貌少女，淡紫衣裙，腰佩細劍，指間夾著細針。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方揚手射出暗器，數點寒光飛出（表現「蚊鬚針」）。`

#### 胡青牛（倚天屠龍記）　代號 `huqingniu`

隊友・治療；成名絕技 「醫術」。

```
金庸武俠人物：胡青牛（倚天屠龍記，明教）。中年醫者，布衣，背著藥箱，愁眉苦臉，身邊飛著一隻蝴蝶。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方遞出藥瓶或丹藥，手上泛出柔和的綠光（表現「醫術」）。`

#### 說不得（倚天屠龍記）　代號 `shuobude`

隊友・控制；成名絕技 「乾坤一氣袋」。

```
金庸武俠人物：說不得（倚天屠龍記，明教五散人）。胖大和尚，笑口常開，肩扛一個巨大的布袋。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：張開巨大布袋向左下方一兜，袋口吸起一陣旋風。`

#### 紀曉芙（倚天屠龍記）　代號 `jixiaofu`

隊友・輔助；成名絕技 「金頂綿掌」。

```
金庸武俠人物：紀曉芙（倚天屠龍記，峨嵋派）。二十多歲溫婉女子，峨嵋素衣，手持長劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：弓步向左下方全力推出一掌，身體前傾，掌前湧出一團掌勁（表現「金頂綿掌」）。`

#### 向問天（笑傲江湖）　代號 `xiangwentian`

隊友・坦；成名絕技 「腕上鐵鍊」。

```
金庸武俠人物：向問天（笑傲江湖，日月神教光明左使）。五十來歲高瘦漢子，灰白長鬚，衣衫襤褸，雙腕繫著斷裂的粗鐵鍊，氣勢豪邁。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：雙臂一甩，腕上兩條粗鐵鍊向左下方呼嘯橫掃。`

#### 寧中則（笑傲江湖）　代號 `ningzhongze`

隊友・攻擊；成名絕技 「無雙無對，寧氏一劍」。

```
金庸武俠人物：寧中則（笑傲江湖，華山派）。四十多歲端莊女俠，淡紫色華山女裝，長髮挽髻，手持長劍，英氣中帶溫柔。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「無雙無對，寧氏一劍」）。`

#### 岳靈珊（笑傲江湖）　代號 `yuelingshan`

隊友・速攻；成名絕技 「玉女劍十九式」、「沖靈劍法」。

```
金庸武俠人物：岳靈珊（笑傲江湖，華山派）。十七八歲嬌俏少女，湖藍華山女裝，雙髻，手持長劍，笑容明朗。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「玉女劍十九式」）。`

#### 劉正風（笑傲江湖）　代號 `liuzhengfeng`

隊友・輔助；成名絕技 「笑傲江湖曲（簫）」。

```
金庸武俠人物：劉正風（笑傲江湖，衡山派）。五十來歲富態儒雅男子，絳色員外袍，手持洞簫，腰佩長劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：吹奏洞簫，簫聲化成一道道淡金色音波向左下方飄去。`

#### 曲洋（笑傲江湖）　代號 `quyang`

隊友・暗器；成名絕技 「黑血神針」、「笑傲江湖曲（琴）」。

```
金庸武俠人物：曲洋（笑傲江湖，日月神教長老）。枯瘦老者，黑色布袍，懷抱瑤琴，鬚髮花白，眉目慈和。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：一手按琴，一手向左下方揚出，一片黑紅色細針飛出（黑血神針）。`

#### 沖虛道長（笑傲江湖）　代號 `chongxu`

隊友・控制；成名絕技 「太極劍」。

```
金庸武俠人物：沖虛道長（笑傲江湖，武當派掌門）。清癯老道，灰白長鬚，藍色武當道袍，手持長劍，背插拂塵。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：長劍向左下方劃出一個個圓圈，劍光連成太極圓弧。`

#### 儀琳（笑傲江湖）　代號 `yilin`

隊友・治療；成名絕技 「天香斷續膠」、「白雲熊膽丸」。

```
金庸武俠人物：儀琳（笑傲江湖，恆山派弟子）。十六七歲清秀小尼姑，灰色緇衣，光頭戴僧帽，雙手捧著藥瓶，神情羞怯。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方遞出藥瓶或丹藥，手上泛出柔和的綠光（表現「天香斷續膠」）。`

#### 不戒和尚（笑傲江湖）　代號 `bujie`

隊友・坦；成名絕技 「不戒蠻勁」。

```
金庸武俠人物：不戒和尚（笑傲江湖，恆山派）。身材魁梧的胖大和尚，袒胸露腹，僧袍油膩，一手抓狗腿、腰掛酒罈。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：把狗腿一甩，空出的大手掌向左下方蠻橫拍出，掌風呼呼。`

#### 桃谷六仙（笑傲江湖）　代號 `taogu`

隊友・控制；成名絕技 「撕人」、「六仙輸真氣」。

```
金庸武俠人物：桃谷六仙（笑傲江湖，桃谷）。六個相貌相似、面如樹皮的怪老頭擠成一團（畫在同一張圖裡，前三後三），衣衫破爛，神情滑稽，正在吵嘴。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：六個人同時向左下方撲出，伸出十幾隻手去抓（撕人）。`

#### 平一指（笑傲江湖）　代號 `pingyizhi`

隊友・治療；成名絕技 「殺人名醫」。

```
金庸武俠人物：平一指（笑傲江湖，殺人名醫）。矮胖短小、腦袋奇大的中年人，藍綢長袍，背著藥箱，手拈銀針。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：一手向左下方擲出一根銀針（殺），另一手捏著一顆冒綠光的藥丸（救）。`

#### 段正明（天龍八部）　代號 `duanzhengming`

隊友・控制；成名絕技 「一陽指」。

```
金庸武俠人物：段正明（天龍八部，大理國保定帝）。五十來歲威嚴帝王，黃色龍袍，頭戴冠冕，鬚髯修整，神情寬厚，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：側身向左下方伸指點出，指尖射出一道細長的亮光（表現「一陽指」）。`

#### 阿朱（天龍八部）　代號 `azhu`

隊友・輔助；成名絕技 「易容術」。

```
金庸武俠人物：阿朱（天龍八部，慕容家侍婢）。十六七歲俏麗溫柔的少女，淡紅衣裙，鵝蛋臉、水汪汪的眼睛，手握一張人皮面具。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：把人皮面具往臉前一晃，身影一半變成別人的模樣，另一手向左下方輕點。`

#### 段正淳（天龍八部）　代號 `duanzhengchun`

隊友・攻擊；成名絕技 「一陽指」。

```
金庸武俠人物：段正淳（天龍八部，大理鎮南王）。四十多歲儒雅王爺，紫色錦袍，頭戴金冠，風流倜儻，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：側身向左下方伸指點出，指尖射出一道細長的亮光（表現「一陽指」）。`

#### 枯榮大師（天龍八部）　代號 `kurong`

隊友・坦；成名絕技 「枯榮禪功」、「少商劍」。

```
金庸武俠人物：枯榮大師（天龍八部，大理天龍寺）。枯瘦老僧，半張臉枯槁如乾屍、半張臉豐潤如常人，灰色僧袍，盤膝而坐。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：雙掌在胸前運氣後向左下方推出，全身有淡青色內力氣旋環繞（表現「枯榮禪功」）。`

#### 王語嫣（天龍八部）　代號 `wangyuyan`

隊友・輔助；成名絕技 「武學指點」。

```
金庸武俠人物：王語嫣（天龍八部，曼陀山莊）。十七八歲絕美少女，淡白衣裙，長髮披肩，手持書卷，氣質嫻雅。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：一手捧書，一手向左下方指去，指尖前方浮現一個發光的破綻記號。`

#### 鍾靈（天龍八部）　代號 `zhongling`

隊友・毒；成名絕技 「閃電貂」。

```
金庸武俠人物：鍾靈（天龍八部，萬劫谷）。十五六歲活潑少女，綠衣，肩頭趴著一隻小貂。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：手一指，肩上的小貂化成一道白色閃電向左下方撲去。`

#### 木婉清（天龍八部）　代號 `muwanqing`

隊友・暗器；成名絕技 「毒袖箭」。

```
金庸武俠人物：木婉清（天龍八部，修羅刀秦紅棉之女）。十八九歲黑衣少女，黑紗蒙面，冷豔，背負長劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：揚起衣袖，袖中射出兩枚泛綠光的小箭飛向左下方。`

#### 薛慕華（天龍八部）　代號 `xuemuhua`

隊友・治療；成名絕技 「閻王敵」。

```
金庸武俠人物：薛慕華（天龍八部，函谷八友）。中年醫者，青布長衫，背著藥箱。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方遞出藥瓶或丹藥，手上泛出柔和的綠光（表現「閻王敵」）。`

#### 蘇星河（天龍八部）　代號 `suxinghe`

隊友・輔助；成名絕技 「珍瓏棋局」。

```
金庸武俠人物：蘇星河（天龍八部，逍遙派）。老者，青衫，手拈棋子，面目和善。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：把一枚棋子往左下方擲出，地面浮現發光的棋盤格紋。`

#### 蘇荃（鹿鼎記）　代號 `suquan`

隊友・控制；成名絕技 「美人三招」。

```
金庸武俠人物：蘇荃（鹿鼎記，神龍教教主夫人）。二十多歲的豔麗女子，紅衣，頭簪金釵，空手，身形婀娜。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：回眸一笑，身子輕旋，一掌向左下方反手拍出（貴妃回眸）。`

#### 茅十八（鹿鼎記）　代號 `maoshiba`

隊友・攻擊；成名絕技 「五虎斷門刀」。

```
金庸武俠人物：茅十八（鹿鼎記，江湖草莽）。三十多歲的粗豪漢子，滿臉鬍鬚，舊黑布短打，手持單刀，身上帶傷。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：揮刀向左下方斜劈，刀身拖出一道寒光弧線（表現「五虎斷門刀」）。`

#### 霍青桐（書劍恩仇錄）　代號 `huoqingtong`

隊友・控制；成名絕技 「三分劍術」、「用兵如神」。

```
金庸武俠人物：霍青桐（書劍恩仇錄，回部首領之女）。二十歲的回部少女，黃衫綠帶，頭上插一根翠綠羽毛，戴回部小帽，腰懸短劍，英氣勃勃。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「三分劍術」）。`

#### 香香公主（書劍恩仇錄）　代號 `xiangxiang`

隊友・輔助；成名絕技 「天生異香」。

```
金庸武俠人物：香香公主（書劍恩仇錄，回部公主）。十七八歲的絕美少女，白色回部衣裙，頭插雪白羽毛，赤足，周身飄著花瓣與蝴蝶。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：輕輕張開雙臂轉身，一陣帶花瓣的淡粉色香氣向左下方飄散。`

#### 無塵道長（書劍恩仇錄）　代號 `wuchen`

隊友・攻擊；成名絕技 「追魂奪命劍」。

```
金庸武俠人物：無塵道長（書劍恩仇錄，紅花會二當家）。五十歲的獨臂道人，青色道袍，單手持長劍，身形精悍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「追魂奪命劍」）。`

#### 趙半山（書劍恩仇錄）　代號 `zhaobanshan`

隊友・暗器；成名絕技 「千臂如來暗器」、「太極拳」。

```
金庸武俠人物：趙半山（書劍恩仇錄，紅花會三當家）。五十歲的胖大和氣漢子，褐色長袍，腰掛暗器囊。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：雙手連揚，數十枚暗器像扇面一樣向左下方散射（千臂如來）。`

#### 文泰來（書劍恩仇錄）　代號 `wentailai`

隊友・攻擊；成名絕技 「奔雷手」。

```
金庸武俠人物：文泰來（書劍恩仇錄，紅花會四當家）。三十多歲的壯漢，濃眉大眼，藏青短打，空手，身上帶著傷痕。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：一掌向左下方劈出，掌前炸開一道白色雷光（奔雷手）。`

#### 駱冰（書劍恩仇錄）　代號 `luobing`

隊友・暗器；成名絕技 「鴛鴦刀與飛刀」。

```
金庸武俠人物：駱冰（書劍恩仇錄，紅花會十一當家）。二十多歲的美麗少婦，紅色勁裝，手握一長一短兩把刀，腰間插著飛刀。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：揮刀向左下方斜劈，刀身拖出一道寒光弧線（表現「鴛鴦刀與飛刀」）。`

#### 余魚同（書劍恩仇錄）　代號 `yuyutong`

隊友・輔助；成名絕技 「金笛」。

```
金庸武俠人物：余魚同（書劍恩仇錄，紅花會十四當家）。二十多歲的書生，淡藍長衫，手持一支金笛，俊雅。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：橫吹金笛，金色音符向左下方飄出。`

#### 陸菲青（書劍恩仇錄）　代號 `lufeiqing`

隊友・暗器；成名絕技 「芙蓉金針」、「柔雲劍術」。

```
金庸武俠人物：陸菲青（書劍恩仇錄，武當派）。六十歲的清瘦老者，扮作塾師，灰色長衫，手持長劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方揚手射出暗器，數點寒光飛出（表現「芙蓉金針」）。`

#### 溫青青（碧血劍）　代號 `wenqingqing`

隊友・速攻；成名絕技 「溫家劍法」。

```
金庸武俠人物：溫青青（碧血劍，石樑溫家）。十八歲的少女，女扮男裝，淡黃色公子長衫，持短劍，眉目嬌俏。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：持劍向左下方疾刺，手臂伸直，劍身帶出一道銀白劍光（表現「溫家劍法」）。`

#### 崔秋山（碧血劍）　代號 `cuiqiushan`

隊友・坦；成名絕技 「伏虎掌」。

```
金庸武俠人物：崔秋山（碧血劍，闖王部屬）。四十歲的豪邁漢子，褐色短打，空手，一臉正氣。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：弓步向左下方全力推出一掌，身體前傾，掌前湧出一團掌勁（表現「伏虎掌」）。`

#### 程靈素（雪山飛狐／飛狐外傳）　代號 `chenglingsu`

隊友・治療；成名絕技 「七心海棠」、「吸毒救人」。

```
金庸武俠人物：程靈素（雪山飛狐／飛狐外傳，毒手藥王關門弟子）。十八歲的瘦小少女，臉色微黃，樸素淡青布衣，背著藥簍，手持一株七色小花。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：手中小花一晃，一縷幾乎透明的七彩毒霧向左下方飄去。`

#### 袁紫衣（雪山飛狐／飛狐外傳）　代號 `yuanziyi`

隊友・速攻；成名絕技 「連奪掌門」。

```
金庸武俠人物：袁紫衣（雪山飛狐／飛狐外傳，後出家為尼）。十八歲的少女，紫色衣裙，手持一條銀絲軟鞭，英氣嬌媚。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方甩出手中的鞭索，鞭身在空中彎成 S 形（表現「連奪掌門」）。`

#### 丁典（連城訣）　代號 `dingdian`

隊友・坦；成名絕技 「神照經」。

```
金庸武俠人物：丁典（連城訣，神照經傳人）。三十多歲的高瘦男子，穿囚衣，琵琶骨上穿著鐵鍊，眼神深情，空手。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：雙掌在胸前運氣後向左下方推出，全身有淡青色內力氣旋環繞（表現「神照經」）。`

#### 史婆婆（俠客行）　代號 `shipopo`

隊友・攻擊；成名絕技 「金烏刀法」。

```
金庸武俠人物：史婆婆（俠客行，史小翠，金烏派創派人）。六十歲的老婦，灰色短衣，頭髮花白，手持單刀。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：揮刀向左下方斜劈，刀身拖出一道寒光弧線（表現「金烏刀法」）。`

#### 石清與閔柔（俠客行）　代號 `shiqingminrou`

隊友・輔助；成名絕技 「上清觀劍法」。

```
金庸武俠人物：石清與閔柔（俠客行，玄素莊）。四十歲的中年夫婦站在一起（畫在同一張圖裡）：石清穿黑衣、閔柔穿白衣，各持一劍。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：黑白兩劍同時向左下方刺出，劍光一黑一白交纏。`

#### 李文秀（白馬嘯西風）　代號 `liwenxiu`

隊友・速攻；成名絕技 「瓦耳拉齊所傳武功」。

```
金庸武俠人物：李文秀（白馬嘯西風，華輝的弟子）。十八歲的漢族少女，哈薩克族服飾，手持一條短馬鞭。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方衝拳或五指成爪抓出，身體前衝，拳爪前帶出氣勁（表現「瓦耳拉齊所傳武功」）。`

#### 計老人（馬家駿）（白馬嘯西風）　代號 `jilaoren`

隊友・暗器；成名絕技 「易容與毒針」。

```
金庸武俠人物：計老人（馬家駿）（白馬嘯西風，瓦耳拉齊的弟子）。佝僂的漢人老頭（其實是中年男子易容），羊皮襖，手提奶茶壺。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：向左下方揚手射出暗器，數點寒光飛出（表現「易容與毒針」）。`

#### 袁冠南與蕭中慧（鴛鴦刀）　代號 `yuanxiao`

隊友・攻擊；成名絕技 「夫妻刀法」。

```
金庸武俠人物：袁冠南與蕭中慧（鴛鴦刀，夫妻刀法傳人）。二十歲的青年男女站在一起（畫在同一張圖裡）：袁冠南穿青衫持鴛刀，蕭中慧穿紅衣持鴦刀。
全身、透明背景、面向左下，大小比例與遊戲裡其他人物相同。平靜的備戰站姿。
```

出招：`同一個人，換成出招的姿勢：兩人背靠背轉身，鴛鴦雙刀一青一紅同時向左下方劈出。`

### 13.4 沿用現有的圖（43 位，不用畫）

這些人物在遊戲裡已經有自己的戰鬥圖，試煉直接沿用。通用門派弟子借用同門派守衛或門派服裝的圖。

| 人物 | 出處 | 沿用的圖 |
|---|---|---|
| 丘處機 | 射鵰英雄傳 | `unit_n_qz_qiuchuji_*` |
| 李莫愁 | 神鵰俠侶 | `unit_n_dl_limochou_*` |
| 洪凌波 | 神鵰俠侶 | `unit_m_gm_hongningbo_*` |
| 孫婆婆 | 神鵰俠侶 | `unit_n_gm_sunpopo_*` |
| 張無忌 | 倚天屠龍記 | `unit_n_zhangwuji_*` |
| 趙敏 | 倚天屠龍記 | `unit_n_wd_zhaomin_*` |
| 張三丰 | 倚天屠龍記 | `unit_n_wd_zhangsanfeng_*` |
| 滅絕師太 | 倚天屠龍記 | `unit_n_em_miejue_*` |
| 阿大（方東白） | 倚天屠龍記 | `unit_n_xx_ada_*` |
| 令狐沖 | 笑傲江湖 | `unit_n_hs_linghuchong_*` |
| 岳不群 | 笑傲江湖 | `unit_n_yuebuqun_*` |
| 莫大先生 | 笑傲江湖 | `unit_n_hn_moda_*` |
| 定閒師太 | 笑傲江湖 | `unit_n_hg_dingxian_*` |
| 勞德諾 | 笑傲江湖 | `unit_n_xx_laodenuo_*` |
| 藍鳳凰 | 笑傲江湖 | `unit_n_lf_lanfenghuang_*` |
| 成不憂 | 笑傲江湖 | `unit_n_hs_chengbuyou_*` |
| 蕭峰（喬峰） | 天龍八部 | `unit_n_xx_qiaofeng_*` |
| 虛竹 | 天龍八部 | `unit_n_xx_xuzhu_*` |
| 丁春秋 | 天龍八部 | `unit_n_xh_dingchunqiu_*` |
| 天山童姥 | 天龍八部 | `unit_n_lj_tonglao_*` |
| 葉二娘 | 天龍八部 | `unit_n_yeerniang_*` |
| 南海鱷神 | 天龍八部 | `unit_n_nanhai_*` |
| 阿紫 | 天龍八部 | `unit_n_xx_azi_*` |
| 韋小寶 | 鹿鼎記 | `unit_n_weixiaobao_*` |
| 雙兒 | 鹿鼎記 | `unit_n_shuanger_*` |
| 陳家洛 | 書劍恩仇錄 | `unit_n_chenjialuo_*` |
| 胡斐 | 雪山飛狐／飛狐外傳 | `unit_n_ym_hufei_*` |
| 血刀老祖 | 連城訣 | `unit_n_xd_laozu_*` |
| 少林武僧 | 通用門派弟子 | `unit_shaolin_m_*` |
| 十八銅人 | 通用門派弟子 | `unit_m_sl_tongren_1_*` |
| 武當道士 | 通用門派弟子 | `unit_m_wd_guard_*` |
| 峨嵋女弟子 | 通用門派弟子 | `unit_m_em_guard_*` |
| 丐幫弟子 | 通用門派弟子 | `unit_gaibang_m_*` |
| 明教教眾 | 通用門派弟子 | `unit_m_dl_mingjiao_*` |
| 日月神教教徒 | 通用門派弟子 | `unit_m_hn_mojiao_*` |
| 全真道士 | 通用門派弟子 | `unit_m_qz_guard_*` |
| 古墓弟子 | 通用門派弟子 | `unit_m_gm_guard_*` |
| 恆山尼姑 | 通用門派弟子 | `unit_m_hg_guard_*` |
| 靈鷲宮弟子 | 通用門派弟子 | `unit_m_lj_guard_*` |
| 星宿弟子 | 通用門派弟子 | `unit_m_xh_guard_*` |
| 血刀僧 | 通用門派弟子 | `unit_m_xd_guard_*` |
| 華山弟子 | 通用門派弟子 | `unit_m_hs_trainee_*` |
| 西夏一品堂武士 | 通用門派弟子 | `unit_n_xx_guard_*` |

### 13.5 數量總結

| 項目 | 人物 | 張數（idle＋attack＋hurt） | 優先 |
|---|---:|---:|---|
| 批次 A | 16 | 48 | 最優先（先做 idle） |
| 批次 B | 20 | 60 | 中 |
| 批次 C | 140 | 420 | 低，可慢慢補 |
| 沿用 | 43 | 0 | — |

---

## 常見問題

- **背景不是透明的怎麼辦？** 請 ChatGPT 「regenerate with a transparent background」。真的做不到也沒關係，純色背景我可以去背。
- **人物面向錯了？** 只要是面向左下或右下都可以，我會翻轉。面向正前方或背面的請重產。
- **大小不一致？** 沒關係，每隻怪物的顯示大小由我在資料裡設定。
- **版權**：AI 產圖由你提供，我在製作人員名單中會標「美術：由開發者使用 AI 工具產生」。
