# opensubsonic.lazycmd

OpenSubsonic 客户端插件，提供分级浏览和后台 `mpv` 播放。

## 功能

- 一级目录显示：`Playlist`、`Artist`、`Album`、`Player`、`Random`、`Starred`、`Search`
- 二级目录：
  - `playlist` -> 歌单列表
  - `artist` -> 艺术家列表
  - `album` -> 专辑列表（默认 `getAlbumList2(type = "newest")`）
- 三级目录：
  - `playlist/<id>` -> 歌单歌曲
  - `artist/<id>/<albumId>` -> 专辑歌曲
  - `album/<albumId>` -> 专辑歌曲
- `player` -> 当前 `mpv` 后台播放列表，与 `mpv` IPC 同步
- `random` -> 随机歌曲列表，来自 `getRandomSongs`
- `starred` -> 收藏歌曲列表，来自 `getStarred2`
- `search` -> 搜索页，按 `s` 输入关键字，先显示 `artist / album / song` 三类结果分组，再进入对应列表
- 在歌曲上按 `Enter`：把“当前歌曲到页尾”的歌曲列表替换到后台 `mpv` 播放列表并开始播放
- 在歌曲上按 `a`：把当前歌曲追加到后台 `mpv` 播放列表
- 在歌单列表上按 `A`：把整个歌单追加到后台 `mpv` 播放列表
- `R`：清缓存并刷新

## 配置

在 `examples/init.lua` 或 `~/.config/lazycmd/init.lua` 中配置：

```lua
{
  dir = 'plugins/opensubsonic.lazycmd',
  config = function()
    require('opensubsonic').setup {
      url = os.getenv 'OPENSUBSONIC_URL',
      username = os.getenv 'OPENSUBSONIC_USER',
      password = os.getenv 'OPENSUBSONIC_PASSWORD',
      -- 或者使用 api_key = os.getenv 'OPENSUBSONIC_API_KEY',

      -- album 根目录默认调用 getAlbumList2(type = "newest")
      album_list_type = 'newest',
      album_list_size = 200,
      random_song_count = 100,
      search_artist_count = 20,
      search_album_count = 20,
      search_song_count = 100,

      stream_format = 'raw',
      max_bitrate = nil,
      -- 默认会为每个 lazycmd 实例生成独立 socket。
      -- 只有你明确想让多个实例共享同一个 mpv 时，才手动固定这个路径。
      mpv_socket = '/tmp/lazycmd-opensubsonic-mpv.sock',
    }
  end,
},
```

默认情况下，插件会为当前 lazycmd 进程生成独立的 `mpv` IPC socket，避免多个实例互相影响。只有显式配置同一个 `mpv_socket` 时，多个实例才会共享同一个 `mpv`。

## 环境变量

- `OPENSUBSONIC_URL`
- `OPENSUBSONIC_USER`
- `OPENSUBSONIC_PASSWORD`
- `OPENSUBSONIC_API_KEY`

`username/password` 与 `api_key` 二选一即可。

## 键位

- `Enter`
  - 普通目录：进入下一级
  - 歌曲页：从当前歌曲开始替换并播放后续队列
  - `player` 页：跳转到选中的播放项
- `a`: 在歌曲上把当前歌曲追加到 `mpv` 队列
- `A`
  - 在歌曲上打开歌单选择框并把歌曲加入目标歌单
  - 在歌单列表上把整个歌单追加到 `mpv` 队列
- `n`
  - 在歌单列表页弹出输入框并创建新歌单
  - 在 `player` 页下一曲
- `dd`
  - 在歌单列表里删除当前歌单，会二次确认
  - 在歌单歌曲列表里移除当前歌曲
- `s`
  - 在歌曲上切换收藏状态
  - 在 `search` 页弹出输入框并提交搜索关键字
- `space`: 在 `player` 页暂停/继续
- `n`: 在 `player` 页下一曲
- `p`: 在 `player` 页上一曲
- `P`: 在 `player` 页恢复播放
- `+`: 在 `player` 页增大音量
- `-`: 在 `player` 页减小音量
- `R`: 清空插件缓存并刷新

## 说明

- 插件通过 OpenSubsonic REST API 拉取 `getPlaylists`、`getPlaylist`、`getArtists`、`getArtist`、`getAlbumList2`、`getAlbum`、`getRandomSongs`、`getStarred2`、`search3`
- 播放使用后台 `mpv` + Unix socket IPC
- 播放链接使用 `/rest/stream`

## 结构

- `opensubsonic/init.lua`: UI、列表渲染、预览和按键绑定
- `opensubsonic/config.lua`: 共享配置和配置归一化
- `opensubsonic/api.lua`: OpenSubsonic 配置读取、鉴权、HTTP 请求和缓存
- `opensubsonic/mpv.lua`: `mpv` 进程管理、IPC 和播放列表状态
