/**
 * bridge.js - Flutter ↔ WebView 通信桥
 *
 * Flutter → JS: window.ChatBridge.xxx()
 * JS → Flutter: window.FlutterBridge.postMessage(JSON.stringify({...}))
 */

const Bridge = {
  /** 发送消息到 Flutter 侧 */
  _post(action, data) {
    try {
      const payload = JSON.stringify({ action, ...data });
      if (window.FlutterBridge) {
        window.FlutterBridge.postMessage(payload);
      }
    } catch (e) {
      console.error('Bridge._post error:', e);
    }
  },

  // ===== JS → Flutter =====
  onReady() { this._post('onReady', {}); },
  onSendMessage(text) { this._post('onSendMessage', { text }); },
  onStopGenerating() { this._post('onStopGenerating', {}); },
  onPickImage() { this._post('onPickImage', {}); },
  onPickFile() { this._post('onPickFile', {}); },
  onRemoveAttachment(path) { this._post('onRemoveAttachment', { path }); },
  onLinkTap(url) { this._post('onLinkTap', { url }); },
  onImageTap(url) { this._post('onImageTap', { url }); },
  onScrollNearTop() { this._post('onScrollNearTop', {}); },
  onToggleStreaming(value) { this._post('onToggleStreaming', { value }); },
  onSelectModel() { this._post('onSelectModel', {}); },
  onMessageAction(id, action) { this._post('onMessageAction', { id, msgAction: action }); },
  onShowAttachmentMenu() { this._post('onShowAttachmentMenu', {}); },
  onUserMessageLongPress(id) { this._post('onUserMessageLongPress', { id }); },
};

window.Bridge = Bridge;
