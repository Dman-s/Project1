import { getCameraWebSocketUrl } from './detection'


export class CameraDetectionClient {
  constructor({
    url = getCameraWebSocketUrl(),
    WebSocketImpl = globalThis.WebSocket,
    onMessage = () => {},
    onError = () => {},
    onOpen = () => {},
    onClose = () => {},
  } = {}) {
    this.url = url
    this.WebSocketImpl = WebSocketImpl
    this.onMessage = onMessage
    this.onError = onError
    this.onOpen = onOpen
    this.onClose = onClose
    this.socket = null
    this.configured = false
    this.awaitingResponse = false
  }

  connect(config) {
    if (!this.WebSocketImpl) throw new Error('当前浏览器不支持 WebSocket')
    const socket = new this.WebSocketImpl(this.url)
    this.socket = socket
    socket.onopen = () => {
      socket.send(JSON.stringify({ type: 'config', ...config }))
      this.onOpen()
    }
    socket.onmessage = (event) => {
      let message
      try {
        message = JSON.parse(event.data)
      } catch {
        this.awaitingResponse = false
        this.onError('摄像头服务返回了无效消息')
        return
      }
      if (message.type === 'config_ok') {
        this.configured = true
        this.awaitingResponse = false
      } else if (message.type === 'result') {
        this.awaitingResponse = false
      } else if (message.type === 'error') {
        this.awaitingResponse = false
        this.onError(message.message || '摄像头检测失败')
      }
      this.onMessage(message)
    }
    socket.onerror = () => {
      this.awaitingResponse = false
      this.onError('摄像头 WebSocket 连接失败')
    }
    socket.onclose = (event) => {
      this.configured = false
      this.awaitingResponse = false
      this.onClose(event)
    }
    return socket
  }

  sendFrame(data) {
    const openState = this.WebSocketImpl?.OPEN ?? 1
    if (
      !this.socket ||
      this.socket.readyState !== openState ||
      !this.configured ||
      this.awaitingResponse
    ) {
      return false
    }
    this.awaitingResponse = true
    this.socket.send(JSON.stringify({ type: 'frame', data }))
    return true
  }

  close() {
    if (!this.socket) return
    const openState = this.WebSocketImpl?.OPEN ?? 1
    if (this.socket.readyState === openState) {
      this.socket.send(JSON.stringify({ type: 'close' }))
      this.socket.close(1000)
    }
    this.socket = null
    this.configured = false
    this.awaitingResponse = false
  }
}
