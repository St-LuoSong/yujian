import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5173,
    host: '0.0.0.0',
    proxy: {
      // 开发时同源代理，浏览器不需要处理跨域，也不需要在管理台内保存后端地址。
      '/api': { target: 'http://localhost:8080', changeOrigin: true },
      '/share': { target: 'http://localhost:8080', changeOrigin: true },
    },
  },
  build: { outDir: 'dist', sourcemap: false },
})
