# opensubsonic.lazycmd

OpenSubsonic 客户端插件，提供分级浏览；播放能力委托给独立的 `mpv.lazycmd` 插件。

## 功能

- 一级目录显示：`Playlist`、`Artist`、`Album`、`Random`、`Starred`、`Search`
- 二级目录：
  - `playlist` -> 歌单列表
  - `artist` -> 艺术家列表
  - `album` -> 专辑列表（默认 `getAlbumList2(type = "newest")`）
- 三级目录：
  - `playlist/<id>` -> 歌单歌曲
  - `artist/<id>/<albumId>` -> 专辑歌曲
  - `album/<albumId>` -> 专辑歌曲
- `random` -> 随机歌曲列表，来自 `getRandomSongs`
- `starred` -> 收藏歌曲列表，来自 `getStarred2`
- `search` -> 搜索页，按 `Enter` 或 `s` 输入关键字，先显示 `Song / Album / Artist` 三类结果分组，再进入对应列表
- 在歌曲上按 `Enter`：把“当前歌曲到页尾”的歌曲列表替换到 `/mpv` 队列并开始播放
- 在歌曲上按 `a`：把当前歌曲追加到 `/mpv` 队列
- 在歌单列表上按 `A`：把整个歌单追加到 `/mpv` 队列
- OpenSubsonic 往 `mpv` 队列塞歌时，会附带自己的星标快捷键和预览
- `R`：清缓存并刷新

## 配置

在 `examples/init.lua` 或 `~/.config/lazycmd/init.lua` 中配置。要让播放生效，请同时配置 `mpv.lazycmd`：

```lua
{
  dir = 'plugins/mpv.lazycmd',
  config = function()
    require('mpv').setup {
      socket = '/tmp/lazycmd-mpv.sock',
    }
  end,
},
{
  dir = 'plugins/opensubsonic.lazycmd',
  config = function()
    require('opensubsonic').setup {
      url = os.getenv 'OPENSUBSONIC_URL',
      username = os.getenv 'OPENSUBSONIC_USER',
      password = os.getenv 'OPENSUBSONIC_PASSWORD',
      -- 或者使用 api_key = os.getenv 'OPENSUBSONIC_API_KEY',

      album_list_type = 'newest',
      album_list_size = 200,
      random_song_count = 100,
      search_artist_count = 20,
      search_album_count = 20,
      search_song_count = 100,

      keymap = {
        append_to_player = 'a',
        add_to_playlist = 'A',
        toggle_star = 's',
        search = 's',
        new = 'n',
        delete = 'dd',
        play_now = '<enter>',
      },

      stream_format = 'raw',
      max_bitrate = nil,
    }
  end,
},
```

`opensubsonic.setup()` 会调用 `lc.plugin.load('mpv')`，因此只要 `plugins` 里已经声明了 `mpv.lazycmd`，就会在进入 OpenSubsonic 前把 `mpv` 的配置先应用好。

## 环境变量

- `OPENSUBSONIC_URL`
- `OPENSUBSONIC_USER`
- `OPENSUBSONIC_PASSWORD`
- `OPENSUBSONIC_API_KEY`

`username/password` 与 `api_key` 二选一即可。

## 键位

- 大部分动作使用 entry 级别 keymap：只有当光标停在支持该动作的条目上时，按键才会生效
- `Enter`
  - 普通目录：进入下一级
  - 歌曲页：从当前歌曲开始替换并播放后续队列
  - `search` 页：发起搜索
- `a`: 在歌曲上把当前歌曲追加到 `mpv` 队列
- `A`
  - 在歌曲上打开歌单选择框并把歌曲加入目标歌单
  - 在歌单列表上把整个歌单追加到 `mpv` 队列
- `n`: 在歌单列表页弹出输入框并创建新歌单
- `dd`
  - 在歌单列表里删除当前歌单，会二次确认
  - 在歌单歌曲列表里移除当前歌曲
- `s`
  - 在歌曲上切换收藏状态
  - 在 `/mpv` 中对 OpenSubsonic 来源的歌曲切换收藏状态
  - 在 `search` 页弹出输入框并提交搜索关键字
- `R`: 清空插件缓存并刷新

具体来说：

- 歌曲条目支持 `Enter` / `a` / `s` / `A`
- 歌单条目支持 `A` / `dd` / `n`
- 搜索相关条目支持 `s` 重新发起搜索
- 空歌单页也会提供对应的 entry 级快捷键
- `/mpv` 页面上的播放控制键位由 `mpv.lazycmd` 提供

## 说明

- 插件通过 OpenSubsonic REST API 拉取 `getPlaylists`、`getPlaylist`、`getArtists`、`getArtist`、`getAlbumList2`、`getAlbum`、`getRandomSongs`、`getStarred2`、`search3`
- 播放链接使用 `/rest/stream`
- 队列展示和播放器控制由独立的 `mpv.lazycmd` 处理

## 结构

- `opensubsonic/init.lua`: UI、列表渲染、预览和按键绑定
- `opensubsonic/config.lua`: 共享配置和配置归一化
- `opensubsonic/api.lua`: OpenSubsonic 配置读取、鉴权、HTTP 请求和缓存
- `opensubsonic/actions.lua`: OpenSubsonic 页面动作，以及往 `mpv` 队列追加带自定义预览/键位的歌曲
