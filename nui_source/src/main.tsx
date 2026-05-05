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

interface SoundData {
	soundId: string;
	soundName: string;
	volume: number;
	looped?: boolean;
	iteration?: number;
	offsetMs?: number;
	reportEvents?: boolean;
}

interface FuncMap {
	[event: string]: (data: any) => void;
}

interface AudioEntry {
	audio: HTMLAudioElement;
	iteration: number;
}

const audios: Record<string, AudioEntry> = {};
const Funcs: FuncMap = {};

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
		delete audios[soundData.soundId];
	}

	const audio = new Audio(`sounds/${soundData.soundName}`);
	const iteration = soundData.iteration ?? 0;
	const shouldReportEvents = soundData.reportEvents === true;

	audio.volume = soundData.volume;
	audio.loop = soundData.looped === true ? true : false;

	audios[soundData.soundId] = {
		audio,
		iteration,
	};

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
			delete audios[soundId];

			return;
		}

		// If not fading the audio, stop it, delete the id and return
		if (fade == 0) {
			audio.pause();
			unregisterAudioEvents(audio);
			delete audios[soundId];
			return;
		}

		// If fading the audio, make sure to delete it instantly to avoid duplicate ids if one is manually provided
		// Then, slowly fade the audio out
		unregisterAudioEvents(audio);
		delete audios[soundId];

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
				delete audios[soundId];
			}
		});
	}
};

Funcs.UpdateSoundVolume = (soundData: { soundId: string; volume: number }) => {
	const entry = audios[soundData.soundId];
	if (!entry) return;

	entry.audio.volume = soundData.volume;
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
