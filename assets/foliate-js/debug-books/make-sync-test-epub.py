# -*- coding: utf-8 -*-
"""Generate a small synthetic EPUB used by the TTS highlight-sync browser
evidence (docs/tts-round2/05-reader-highlight-sync.md).

The book is written for this test only (no copyrighted content). It contains:
- Chinese sentences with `。！？` terminators,
- a footnote link inside a sentence and one after a sentence,
- a bare `[12]` annotation that is *not* a link (the pipeline excludes it from
  the spoken ranges, so it must not be highlighted either),
- a very long single sentence that spans several pages,
- three sections, so cross-section navigation can be exercised.

Run:
    <python> make-sync-test-epub.py
It writes sync-test.epub next to this script.
"""

import os
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "sync-test.epub")

XHTML_HEAD = """<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN">
<head>
  <meta charset="utf-8"/>
  <title>{title}</title>
  <style>
    body {{ line-height: 1.6; }}
    p {{ margin: 0.6em 0; }}
    aside.footnote {{ border-top: 1px solid #999; margin-top: 2em; }}
  </style>
</head>
<body>
{body}
</body>
</html>
"""

# A single, very long sentence (one full stop at the very end). It must be long
# enough to spill over more than one page in a 1280x800 window, so the pipeline
# can paint the ".a" half and then the ".b" half of it.
LONG_SENTENCE_CLAUSES = [
    "那是一条为了验证跨页高亮而特意写长的句子",
    "它沿着河岸慢慢展开",
    "先经过一棵老槐树",
    "再绕过几块被水磨圆的青石",
    "然后钻进沙沙作响的竹林",
    "接着爬上一段缓坡",
    "最后消失在山腰的白雾里",
    "长句第一段写的是风景",
    "长句第二段写的是心情",
    "长句第三段写的是回忆",
    "长句第四段写的是期待",
    "长句第五段写的是告别",
    "长句第六段写的是重逢",
    "长句第七段写的是沉默",
    "长句第八段写的是风声",
    "长句第九段写的是归途",
]
# Padding so the single sentence is long enough to cross several 1280x800
# pages. Generated (not copied) filler text.
LONG_SENTENCE_CLAUSES += [
    f"长句补写第{index}小段写的是山路的第{index}个转弯处" for index in range(1, 41)
]
LONG_SENTENCE_CLAUSES += [
    "句子到这里终于快要结束了",
    "却还要再补上一小段",
    "好让它稳稳地跨过两页甚至三页",
    "最后才用一个句号收住",
]
LONG_SENTENCE = "，".join(LONG_SENTENCE_CLAUSES) + "。"

CH1_BODY = f"""
<h1>第一章 归途</h1>
<p id="p1">黄昏时分，山道上的风渐渐凉了。<strong>陈望</strong>把外衣裹紧，沿着石阶一步一步往山下走。他听见远处传来几声犬吠，又很快被风吹散了。</p>
<p id="p2">他在村口停下脚步，抬头看了看天。<sup><a href="#fn1" id="fnref1">[1]</a></sup>云层压得很低，像是要下雨的样子。他想起母亲说过的话：出门在外，别忘了带伞。</p>
<p id="p3">他停下来<sup><a href="#fn1" id="fnref2">[2]</a></sup>想了想，又继续往前走。路边的野草沾着露水，打湿了他的裤脚。</p>
<p id="p4">他在笔记上写下日期<sup>[12]</sup>，然后合上了本子。远处的灯火一盏一盏亮起来，像是有人在山谷里撒了一把碎金。</p>
<p id="p5">峡口的风比山道上更硬，吹得人睁不开眼。陈望靠在岩石上歇了一会儿，听见溪水从脚边流过，声音清亮得像一串铃铛。他忽然想起很多年前的一个冬天，也是这样一个人在山上走。</p>
<p id="p6">{LONG_SENTENCE}</p>
<p id="p7">夜色彻底落下来的时候，他终于看见了山脚的灯火。那里有他熟悉的屋顶，有一盏一直亮着的窗，有一扇永远为他留着的门。他加快了脚步，心跳也跟着快了起来。</p>
<p id="p8">母亲在门口等他。她没有说话，只是接过他的行囊，转身往屋里走。灶上的水已经烧开，热气把窗玻璃蒙成了一片白。陈望坐下，捧起那碗热汤，忽然觉得一路的风霜都散尽了。</p>
<p id="p9">吃过饭，他走到院子里看天。云已经散了，星星一颗一颗亮起来。远处传来几声犬吠，和傍晚听到的一模一样。他笑了笑，觉得这座山、这个村子，其实什么都没有变。</p>
<p id="p10">他推开木门<sup><a href="#fn1" id="fnref4">[4]</a></sup><br/>院子里静悄悄的。<br/>墙角的梅树落了一地花瓣，香味很淡，却一直跟着他走进了堂屋。</p>
<aside class="footnote" epub:type="footnotes">
  <hr/>
  <aside id="fn1"><p>[1] 脚注：陈望是本书的主人公，这是他多年后第一次回乡。</p></aside>
</aside>
"""

CH2_BODY = """
<h1>第二章 夜渡</h1>
<p id="q1">渡口的夜很静，只有水声一下一下拍着木岸。船工把缆绳解开，招呼最后一个客人上船。陈望坐在船尾，把帽檐压低了些，看着岸上的灯一盏一盏往后退。</p>
<p id="q2">船到河心的时候起了风，水面皱成一片碎银。船工说这条河每年都要吞掉几个人，说这话时语气平静得像在讲别人的故事。陈望没有说话，只是把手伸进水里，凉意顺着指尖一直爬到心里。</p>
<p id="q3">河对岸是一片黑黢黢的树林，林子后面才是官道。船靠岸的时候，船工用竹竿在岸上一点，船身轻轻一荡，陈望扶住船舷站稳了。他付了钱，道了谢，走上那条通往官道的小路。</p>
<p id="q4">林子里的路比想象中难走，树根横七竖八地缠着地面。<sup><a href="#fn2" id="fnref3">[3]</a></sup>陈望点起一盏小灯，光圈只照亮脚边一小块地方。他走得很慢，却一点也不着急。</p>
<p id="q5">走到林子尽头时，天边已经泛白。官道在晨雾里伸向远方，像一条没有尽头的灰线。陈望收起灯，拍了拍衣襟上的露水，抬脚往东走去。</p>
<p id="q6">他走了大约半个时辰，遇见一个推着独轮车的老人。老人问他从哪里来，要到哪里去。陈望想了想，说从山那边来，到很远的地方去。老人笑了笑，说年轻真好，说完就推着车走远了。</p>
<aside class="footnote" epub:type="footnotes">
  <hr/>
  <aside id="fn2"><p>[3] 脚注：夜渡一段对应的是陈望离乡的那一年。</p></aside>
</aside>
"""

CH3_BODY = """
<h1>第三章 灯火</h1>
<p id="r1">多年以后，陈望又一次坐在这条渡船上，只是这一次是从对岸回来。船工换了人，船也比记忆里小了许多。他望着河面，忽然分不清这是清晨还是黄昏。</p>
<p id="r2">渡口边多了一盏路灯，灯下站着一个等他的人。那人远远地朝他挥手，动作很轻，像是怕惊动了什么。陈望也抬起手，隔着水面，慢慢地挥了一下。</p>
<p id="r3">他终于明白，所谓归途，不过是这样一盏灯，这样一个人，在这样一个安静的渡口，等着你从水上回来。</p>
"""


def chapter_xhtml(title, body):
    return XHTML_HEAD.format(title=title, body=body)


CHAPTERS = [
    ("ch1.xhtml", "第一章 归途", CH1_BODY),
    ("ch2.xhtml", "第二章 夜渡", CH2_BODY),
    ("ch3.xhtml", "第三章 灯火", CH3_BODY),
]

CONTAINER = """<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

OPF = """<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="zh-CN">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">anx-tts-sync-test</dc:identifier>
    <dc:title>朗读高亮同步合成测试书</dc:title>
    <dc:language>zh-CN</dc:language>
    <dc:creator>anx-reader-ext tests</dc:creator>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch3" href="ch3.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
    <itemref idref="ch3"/>
  </spine>
</package>
"""

NAV = """<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><meta charset="utf-8"/><title>目录</title></head>
<body>
  <nav epub:type="toc">
    <ol>
      <li><a href="ch1.xhtml">第一章 归途</a></li>
      <li><a href="ch2.xhtml">第二章 夜渡</a></li>
      <li><a href="ch3.xhtml">第三章 灯火</a></li>
    </ol>
  </nav>
</body>
</html>
"""


def main():
    with zipfile.ZipFile(OUT, "w") as z:
        # mimetype must be the first entry and stored uncompressed.
        z.writestr(
            zipfile.ZipInfo("mimetype"),
            "application/epub+zip",
            compress_type=zipfile.ZIP_STORED,
        )
        z.writestr("META-INF/container.xml", CONTAINER, zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/content.opf", OPF, zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/nav.xhtml", NAV, zipfile.ZIP_DEFLATED)
        for name, title, body in CHAPTERS:
            z.writestr(
                "OEBPS/" + name,
                chapter_xhtml(title, body),
                zipfile.ZIP_DEFLATED,
            )
    long_len = len(LONG_SENTENCE)
    print(f"wrote {OUT} ({os.path.getsize(OUT)} bytes), long sentence {long_len} chars")


if __name__ == "__main__":
    main()
