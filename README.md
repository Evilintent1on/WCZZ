# WCZZ

微信插件（iOS）

## 功能

- 红包详情：显示红包领取详情浮层
- 长按菜单：自定义消息长按菜单
- 群助手：**所有群聊默认收进「群助手」这一项**（微信助手的做法）
  - 会话列表里会出现一个「群助手」入口（未读汇总、置顶），点它进入插件自己的分组列表页
  - 分组列表页右上角「＋」可以把**任意会话**手动加进分组；左滑「移出分组」
  - 群聊信息页有「设为常用群（不折叠）」开关 —— 设过的群不进分组，留在会话列表
  - 设置页（WCZZ → 群助手）：开关 / 分组名称 / 常用群列表 / 调试日志
  - 实现：`-[MMNewSessionMgr GetSessionInfoList]` 里摘掉分组内会话并插入合成入口会话；点按在
    `-[NewMainFrameViewController tableView:didSelectRowAtIndexPath:]` 拦截；打开会话走 `-onLogicOpenSession:`
  - 判断群聊：username 以 `@chatroom` 结尾

## 构建

CI 自动构建，产物为 deb 安装包。
