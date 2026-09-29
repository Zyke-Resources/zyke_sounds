import ReactDOM from "react-dom/client";

import "./styling/base_defaults.css";
import "./styling/index.css";
import "./styling/text.css";
import "./styling/inputs.css";
import App from "./components/App";

// Mount the React app for the configuration UI
const rootEl = document.getElementById("root");
if (rootEl) {
	ReactDOM.createRoot(rootEl).render(<App />);
}

interface SpatialData {
	x: number;
	y: number;
	z: number;
	gain: number;
	lowpass?: number;
}

interface SoundData {
	soundId: string;
	soundName: string;
	volume: number;
	spatial?: SpatialData | null;
	looped?: boolean;
	iteration?: number;
	offsetMs?: number;
	reportEvents?: boolean;
}

interface FuncMap {
	[event: string]: (data: any) => void;
}

interface SpatialNodes {
	source: MediaElementAudioSourceNode;
	level: GainNode;
	filter: BiquadFilterNode;
	gain: GainNode;
	panner: PannerNode;
}

interface AudioEntry {
	audio: HTMLAudioElement;
	iteration: number;
	nodes: SpatialNodes | null;
}

const audios: Record<string, AudioEntry> = {};
const Funcs: FuncMap = {};

// Seconds for direction and muffling to glide to each new value between Lua updates
const spatialSmoothing = 0.06;
// Volume glides too; stepping it every Lua update clicks audibly on pure tones
const volumeSmoothing = 0.05;
const openLowpass = 22000;

let audioContext: AudioContext | null = null;

// One shared context; sounds fall back to plain playback if Web Audio is unavailable
const getAudioContext = () => {
	if (!audioContext) {
		try {
			audioContext = new AudioContext();
		} catch (err) {
			console.error("Web Audio unavailable, sounds will play without direction:", err);
			return null;
		}
	}

	if (audioContext.state === "suspended") audioContext.resume().catch(() => {});

	return audioContext;
};

// The element keeps loading, looping and events; the graph owns volume, muffling and direction
const createSpatialNodes = (audio: HTMLAudioElement): SpatialNodes | null => {
	const ctx = getAudioContext();
	if (!ctx) return null;

	try {
		const source = ctx.createMediaElementSource(audio);
		const level = ctx.createGain();
		const filter = ctx.createBiquadFilter();
		const gain = ctx.createGain();
		const panner = ctx.createPanner();

		filter.type = "lowpass";
		filter.frequency.value = openLowpass;

		// Lua already scales volume by distance, so the panner only places the sound. HRTF swaps
		// convolution kernels as the direction changes and crackles, equal-power pans cleanly
		panner.panningModel = "equalpower";
		panner.distanceModel = "linear";
		panner.rolloffFactor = 0;
		panner.positionZ.value = -1;

		source.connect(level).connect(filter).connect(gain).connect(panner).connect(ctx.destination);

		return { source, level, filter, gain, panner };
	} catch (err) {
		console.error("Failed to create spatial audio nodes:", err);
		return null;
	}
};

// New sounds start at their values, gliding there from open would play the first moment unmuffled
const applySpatial = (entry: AudioEntry, spatial?: SpatialData | null, immediate = false) => {
	const nodes = entry.nodes;
	if (!nodes || !audioContext) return;

	const now = audioContext.currentTime;
	const { filter, gain, panner } = nodes;

	// No spatial data means centred and unmuffled, like the player's own sounds
	const x = spatial ? spatial.x : 0;
	const y = spatial ? spatial.y : 0;
	const z = spatial ? spatial.z : -1;

	if (immediate) {
		panner.positionX.value = x;
		panner.positionY.value = y;
		panner.positionZ.value = z;
		gain.gain.value = spatial ? spatial.gain : 1;
		filter.frequency.value = spatial?.lowpass ?? openLowpass;
		return;
	}

	panner.positionX.setTargetAtTime(x, now, spatialSmoothing);
	panner.positionY.setTargetAtTime(y, now, spatialSmoothing);
	panner.positionZ.setTargetAtTime(z, now, spatialSmoothing);
	gain.gain.setTargetAtTime(spatial ? spatial.gain : 1, now, spatialSmoothing * 2);
	filter.frequency.setTargetAtTime(spatial?.lowpass ?? openLowpass, now, spatialSmoothing * 2);
};

// A connected element stays referenced by the graph, so every finished sound must be detached
const releaseNodes = (entry: AudioEntry) => {
	if (!entry.nodes) return;

	try {
		entry.nodes.source.disconnect();
		entry.nodes.panner.disconnect();
	} catch (err) {
		console.error("Failed to release spatial audio nodes:", err);
	}

	entry.nodes = null;
};

// Plain elements fall back to the stepped element volume
const setEntryVolume = (entry: AudioEntry, volume: number, immediate = false) => {
	if (!entry.nodes || !audioContext) {
		entry.audio.volume = volume;
		return;
	}

	const level = entry.nodes.level.gain;
	if (immediate) {
		level.value = volume;
		return;
	}

	level.setTargetAtTime(volume, audioContext.currentTime, volumeSmoothing);
};

const releaseWhenEnded = (entry: AudioEntry) => {
	entry.audio.addEventListener("ended", () => releaseNodes(entry), { once: true });
};

const getSoundUrl = (soundName: string) => {
	// Server-side validation should already provide a safe relative sound name
	// The browser still encodes each path segment before creating the URL
	const segments = soundName.replace(/\\/g, "/").split("/");

	if (segments.some((segment) => segment === "" || segment === "." || segment === "..")) {
		return null;
	}

	return `sounds/${segments.map((segment) => encodeURIComponent(segment)).join("/")}`;
};

window.addEventListener("message", (e: MessageEvent) => {
	const event = e.data.event as string;
	const data = e.data.data;

	if (Funcs[event]) Funcs[event](data);
});

const unregisterAudioEvents = (audio: HTMLAudioElement) => {
	audio.onended = null;
	audio.oncanplay = null;
	audio.onplay = null;
	audio.onloadedmetadata = null;
	audio.onerror = null;
};

Funcs.PlaySound = (soundData: SoundData) => {
	const existingEntry = audios[soundData.soundId];
	if (existingEntry) {
		existingEntry.audio.pause();
		unregisterAudioEvents(existingEntry.audio);
		releaseNodes(existingEntry);
		delete audios[soundData.soundId];
	}

	const soundUrl = getSoundUrl(soundData.soundName);
	if (!soundUrl) {
		console.error("Rejected unsafe sound path:", soundData.soundName);
		return;
	}

	const audio = new Audio(soundUrl);
	const iteration = soundData.iteration ?? 0;
	const shouldReportEvents = soundData.reportEvents === true;

	audio.loop = soundData.looped === true ? true : false;

	const newEntry: AudioEntry = {
		audio,
		iteration,
		nodes: createSpatialNodes(audio),
	};

	audios[soundData.soundId] = newEntry;
	setEntryVolume(newEntry, soundData.volume, true);
	applySpatial(newEntry, soundData.spatial, true);

	let hasStarted = false;
	let hasSentMetadata = false;
	let fallbackTimer: ReturnType<typeof setTimeout> | null = null;

	const getDurationMs = () => {
		if (!Number.isFinite(audio.duration) || audio.duration <= 0) return 0;

		return Math.floor(audio.duration * 1000);
	};

	const clearFallbackTimer = () => {
		if (!fallbackTimer) return;

		clearTimeout(fallbackTimer);
		fallbackTimer = null;
	};

	const cleanupAudio = () => {
		const entry = audios[soundData.soundId];
		if (!entry || entry.iteration !== iteration) return;

		clearFallbackTimer();
		unregisterAudioEvents(audio);
		releaseNodes(entry);
		delete audios[soundData.soundId];
	};

	const sendMetadata = (durationMs: number) => {
		if (!shouldReportEvents || durationMs <= 0 || hasSentMetadata) return;

		hasSentMetadata = true;

		send("SoundMetadata", {
			soundId: soundData.soundId,
			soundName: soundData.soundName,
			iteration,
			durationMs,
			reportEvents: true,
		});
	};

	const trySendMetadata = () => {
		sendMetadata(getDurationMs());
	};

	const sendEnded = (failed = false) => {
		const entry = audios[soundData.soundId];
		if (!entry || entry.iteration !== iteration) return;

		send("SoundEnded", {
			soundId: soundData.soundId,
			soundName: soundData.soundName,
			iteration,
			durationMs: getDurationMs(),
			failed,
			reportEvents: shouldReportEvents,
		});

		cleanupAudio();
	};

	const startAudio = () => {
		if (hasStarted) return;

		const entry = audios[soundData.soundId];
		if (!entry || entry.iteration !== iteration) {
			clearFallbackTimer();
			return;
		}

		hasStarted = true;
		clearFallbackTimer();

		const durationMs = getDurationMs();
		const offsetMs = Math.max(0, soundData.offsetMs ?? 0);
		let offsetSeconds = offsetMs / 1000;

		sendMetadata(durationMs);

		if (durationMs > 0) {
			if (audio.loop) {
				offsetSeconds = (offsetMs % durationMs) / 1000;
			} else if (offsetMs >= durationMs) {
				sendEnded();
				return;
			}
		}

		if (offsetSeconds > 0) {
			try {
				audio.currentTime = offsetSeconds;
			} catch (err) {
				console.error("Failed to sync sound offset:", err);
			}
		}

		audio.play().catch((err) => {
			console.error("Failed to play sound:", err);
			sendEnded(true);
		});
	};

	audio.onloadedmetadata = () => {
		trySendMetadata();

		if (!hasStarted) {
			startAudio();
		}
	};

	audio.onerror = () => {
		console.error("Failed to load sound:", soundData.soundName);
		sendEnded(true);
	};

	if (!audio.loop) {
		audio.onended = () => {
			sendEnded();
		};
	}

	audio.load();

	if (audio.readyState >= 1 || (soundData.offsetMs ?? 0) <= 0) {
		startAudio();
	} else {
		fallbackTimer = setTimeout(startAudio, 500);
	}
};

Funcs.StopSound = ({
	soundId,
	fade = 0, // Fade sound in ms, defaults to no fade
	forceFull = false, // Force audio to fully play, ignores fade & if audio has not yet started
}: {
	soundId: string;
	fade?: number;
	forceFull?: boolean;
}) => {
	const entry = audios[soundId];
	if (!entry) return;

	const audio = entry.audio;

	const hasStarted = audio.played.length !== 0;
	if (hasStarted) {
		// If forcing the full audio, simply set loop to false, delete the id and let it play out
		if (forceFull) {
			audio.loop = false;
			unregisterAudioEvents(audio);
			releaseWhenEnded(entry);
			delete audios[soundId];

			return;
		}

		// If not fading the audio, stop it, delete the id and return
		if (fade == 0) {
			audio.pause();
			unregisterAudioEvents(audio);
			releaseNodes(entry);
			delete audios[soundId];
			return;
		}

		// If fading the audio, make sure to delete it instantly to avoid duplicate ids if one is manually provided
		// Then, slowly fade the audio out
		unregisterAudioEvents(audio);
		delete audios[soundId];

		// Graph sounds ramp their gain smoothly instead of stepping the element volume
		if (entry.nodes && audioContext) {
			const level = entry.nodes.level.gain;
			const now = audioContext.currentTime;

			level.cancelScheduledValues(now);
			level.setValueAtTime(level.value, now);
			level.linearRampToValueAtTime(0, now + fade / 1000);

			setTimeout(() => {
				audio.pause();
				releaseNodes(entry);
			}, fade);

			return;
		}

		const orgVolume = audio.volume;
		const interval = 20;
		const steps = Math.max(1, Math.floor(fade / interval));
		const stepSize = orgVolume / steps;

		let currStep = 0;
		let newVolume = orgVolume;
		const fadeInterval = setInterval(() => {
			if (currStep >= steps) {
				clearInterval(fadeInterval);
				audio.pause();
				releaseNodes(entry);
				return;
			}

			currStep += 1;
			newVolume -= stepSize;
			if (newVolume < 0.0) {
				newVolume = 0.0;
				currStep = steps;
			}

			audio.volume = newVolume;
		}, interval);
	} else {
		audio.addEventListener("canplay", () => {
			if (audios[soundId]) {
				audios[soundId].audio.pause();
				unregisterAudioEvents(audios[soundId].audio);
				releaseNodes(audios[soundId]);
				delete audios[soundId];
			}
		});
	}
};

Funcs.UpdateSoundVolume = (soundData: { soundId: string; volume: number; spatial?: SpatialData | null }) => {
	const entry = audios[soundData.soundId];
	if (!entry) return;

	setEntryVolume(entry, soundData.volume);
	applySpatial(entry, soundData.spatial);
};

// Helper to send NUI events back to Lua (used by sound logic)
function send(eventName: string, data: any): void {
	fetch("https://zyke_sounds/Eventhandler", {
		method: "POST",
		headers: {
			"Content-type": "application/json; charset=UTF-8",
		},
		body: JSON.stringify({
			event: eventName,
			data: data,
		}),
	});
}
