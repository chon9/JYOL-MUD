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

## 常見問題

- **背景不是透明的怎麼辦？** 請 ChatGPT 「regenerate with a transparent background」。真的做不到也沒關係，純色背景我可以去背。
- **人物面向錯了？** 只要是面向左下或右下都可以，我會翻轉。面向正前方或背面的請重產。
- **大小不一致？** 沒關係，每隻怪物的顯示大小由我在資料裡設定。
- **版權**：AI 產圖由你提供，我在製作人員名單中會標「美術：由開發者使用 AI 工具產生」。
