import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import process from "node:process";

export default defineConfig(({ command }) => {
    if (command === "build") process.env.NODE_ENV = "production";

    return {
        plugins: [react()],
        base: "./",
        build: {
            outDir: "./../nui",
            emptyOutDir: true,
            assetsDir: "",
            rollupOptions: {
                output: {
                    entryFileNames: "[name].js",
                    chunkFileNames: "[name].js",
                    assetFileNames: "[name].[ext]",
                },
            },
        },
        server: {
            host: "127.0.0.1",
            port: 5174,
        },
    };
});
