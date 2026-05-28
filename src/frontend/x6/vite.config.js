import { defineConfig } from 'vite'

export default defineConfig({
  build: {
    outDir: 'build',
    emptyOutDir: true,
    sourcemap: true,
    lib: {
      entry: './diagram.js',
      name: 'Diagram',
      fileName: () => 'diagram.js',
      formats: ['es']
    }
  }
})
