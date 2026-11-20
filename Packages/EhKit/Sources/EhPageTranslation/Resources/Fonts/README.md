# Fonts for page translation

Three faces, one for each kind of lettering. Each file is a subset of its original: the 6,763
characters of GB2312, ASCII and the punctuation vertical Chinese needs, with every layout
feature kept (the vertical forms `vert` and `vrt2` among them). All three are under the SIL
Open Font License 1.1; the licence of each is the text file beside it.

| File | Used for | Original | Licence |
|---|---|---|---|
| `NotoSansSC-VF-GB2312.ttf` | Dialogue, and bold for shouting (variable weight) | Noto Sans SC 2.004, `ofl/notosanssc/NotoSansSC[wght].ttf` of github.com/google/fonts | `NotoSansSC-OFL.txt` |
| `NotoSerifSC-VF-GB2312.ttf` | Captions in boxes (variable weight) | Noto Serif SC 2.003, `ofl/notoserifsc/NotoSerifSC[wght].ttf` of github.com/google/fonts | `NotoSerifSC-OFL.txt` |
| `EhShokoKai-Regular.ttf` | Text outside balloons | LXGW WenKai 1.530 Regular, github.com/lxgw/LxgwWenKai | `EhShokoKai-OFL.txt` |

`EhShokoKai-Regular.ttf` is a modified version of LXGW WenKai. That font has Reserved Font
Names, and its licence lets a subset keep them only for web fonts, so this subset has another
name (family "EhShoko Kai"). Its glyphs, copyright and licence records are unchanged. The two
Noto subsets keep their names: neither name is reserved.

The subsets were made with fontTools' subsetter (`layout_features = ['*']`, `name_IDs = ['*']`,
`notdef_outline = True`) over the characters above.
