const fs = require("fs");
const path = require("path");

const validExtensions = new Set([".mp3", ".ogg", ".wav"]);
const soundRoot = path.join(GetResourcePath(GetCurrentResourceName()), "nui", "sounds");
const sounds = [];

function scanDirectory(directory) {
	let entries = [];

	try {
		entries = fs.readdirSync(directory, { withFileTypes: true });
	} catch (err) {
		console.log(`^1[ERROR] Zyke Sounds could not scan ${directory}: ${err.message}^7`);

		return;
	}

	for (const entry of entries) {
		const fullPath = path.join(directory, entry.name);

		if (entry.isDirectory()) {
			scanDirectory(fullPath);
			continue;
		}

		if (!entry.isFile()) continue;

		const extension = path.extname(entry.name).toLowerCase();
		if (!validExtensions.has(extension)) continue;

		sounds.push(path.relative(soundRoot, fullPath).split(path.sep).join("/"));
	}
}

scanDirectory(soundRoot);
sounds.sort((a, b) => a.localeCompare(b));

exports("GetDiscoveredSounds", () => sounds);
