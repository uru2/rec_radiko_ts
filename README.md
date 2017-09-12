# rec_radiko_ts
ラジコタイムフリーの番組を保存するシェルスクリプトです。  
必要な外部ツールは最小限に、またash,dashでも動作するよう努めています。


## 必要なもの
- curl
- libxml2 (xmllintのみ使用)
- FFmpeg (3.x以降 要AAC,HLSサポート)

## 使い方
```
$ ./rec_radiko_ts.sh [options]
```

| 引数 | 必須 |説明 |備考 |
|:-:|:-:|:-|:-|
|-s _STATION_|○|放送局ID|ラジコサイトの番組表から番組詳細ページへ移動したあとのURL  /#!/ts/`???`/ にあたる文字 <sup>[*1](#param_note1)</sup>|
|-f _DATETIME_|○|開始日時|JSTでの日時 %Y%m%d%H%M形式|
|-t _DATETIME_|△<sup>[*2](#param_note2)</sup>|終了日時|JSTでの日時 %Y%m%d%H%M形式 <sup>[*3](#param_note3)</sup>|
|-d _MINUTE_|△<sup>[*2](#param_note2)</sup>|録音時間(分)|`-f` で指定した時間に加算することで終了日時を計算する <sup>[*3](#param_note3)</sup>|
|-u _URL_||番組URL|ラジコサイトの番組表から番組詳細ページへ移動したあとのURLを元に `-s` `-f` `-t` の値を自動で取得する|
|-m _MAIL_||ラジコプレミアム メールアドレス||
|-p _PASSWORD_||ラジコプレミアム パスワード||
|-o _PATH_||出力パス|未指定の場合カレントディレクトリに `放送局ID_開始日時_終了日時.m4a` というファイルを作成|

<a id="param_note1" name="param_note1">*1</a> http://radiko.jp/v3/station/region/full.xml のIDと同じ。  
<a id="param_note2" name="param_note2">*2</a> どちらかのオプションを指定すること。`-t` および `-d` の両方が指定されていた場合、終了日時は長くなるほうに合わせる。  
<a id="param_note3" name="param_note3">*3</a> 終了日時はスクリプトを実行する日時-2分前までになるよう指定すること。未来の日時を指定したりスクリプト実行直前の日時を指定した場合はエラーが発生、または再生できないファイルが生成されることがある。  


## 実行例
```
# エリア内の局
$ ./rec_radiko_ts.sh -s RN1 -f 201705020825 -t 201705020835 -o "/hoge/2017-05-02 日経電子版NEWS(朝).m4a"
# エリア外の局 (エリアフリー)
$ ./rec_radiko_ts.sh -s YBC -f 201704300855 -t 201704300900 -o "/hoge/2017-04-30 ラジオで詰め将棋.m4a" -m "foo@example.com" -p "password"
# 終了日時ではなく録音時間で指定
$ ./rec_radiko_ts.sh -s RN1 -f 201705020825 -d 10
# 番組URLから
$ ./rec_radiko_ts.sh -u 'http://radiko.jp/#!/ts/YFM/20170603223000'
```

もっとも単体で動かすよりはcronとして以下のように仕掛けると便利でしょう。
```
37 8 * * 1,2,3,4,5 rec_radiko_ts.sh -s RN1 -f "`date +\%Y\%m\%d`0825" -t "`date +\%Y\%m\%d`0835" -o "/hoge/`date +\%Y-\%m-\%d` 日経電子版NEWS(朝).m4a"
```


## 動作確認環境
- Ubuntu 16.04.2
    - curl 7.47.0
    - xmllint using libxml version 20903
    - ffmpeg 3.3.3-1ubuntu1~16.04.york0
- FreeBSD 11.0-RELEASE
    - curl 7.55.1
    - xmllint using libxml version 20904
    - ffmpeg 3.3.3

余談ですが、Windows 10 Creators UpdateビルドでのWindows Subsystem for LinuxのUbuntuでも動作します。


## 備考
- `-f` および `-t` を同一日時(または `-d 0` )にした場合にm4aは0分ではなく5分間のデータとなりますが、これはラジコ側の ~~バグ~~ 仕様のようです。
    - プレイリストAPIでは5秒単位で時間指定できますが、時間の差を1〜5秒に指定した場合はきちんと5秒のデータが作成されます。 ~~(やっぱりこれバグじゃない?)~~


##  作った人
うる。 ([@uru_2](https://twitter.com/uru_2))


## ライセンス
[MIT License](LICENSE)


## 謝辞
下記のソースコード・情報を参考にさせていただきました。

- https://github.com/ez-design/RTFree
- http://kyoshiaki.hatenablog.com/entry/2014/05/04/184748
- http://mizukifu.blog29.fc2.com/blog-entry-1429.html
- https://github.com/ShellShoccar-jpn/misc-tools/blob/master/utconv

RTFreeは実装方法および .NET Core 入れて動かすのちょっとなぁ…という気持ちにさせてくれたという意味で特に感謝しております。
