import { memo, useState } from "react";
import { listen, send, callback } from "../utils/nui";
import { useModalContext } from "../context/ModalContext";
import { useTranslation } from "../context/Translation";
import Modal from "./Modal";
import Slider from "./Slider";
import VolumeUpIcon from "@mui/icons-material/VolumeUp";

interface SoundEntry {
	name: string;
	volume: number;
}

const SoundRow = memo(({ name, initialVolume }: { name: string; initialVolume: number }) => {
	const [volume, setVolume] = useState(initialVolume);

	return (
		<Slider
			label={name}
			displayLabel={`${volume.toFixed(2)}x`}
			value={volume}
			onChange={setVolume}
			onChangeEnd={(val) => send("SetSoundVolume", { name, volume: val })}
			min={0}
			max={2}
			step={0.05}
		/>
	);
});

const SoundConfigMenu = () => {
	const T = useTranslation();
	const { openModal, closeModal } = useModalContext();
	const [sounds, setSounds] = useState<SoundEntry[]>([]);
	const [loadingSounds, setLoadingSounds] = useState(false);

	listen("SetOpen", async (val: boolean) => {
		if (val) {
			setLoadingSounds(true);
			openModal("soundConfig");

			const delay = (ms: number) => new Promise((res) => setTimeout(res, ms));
			const sounds = callback("GetSoundsList");

			await delay(200);
			setSounds(await sounds as SoundEntry[]);
			setLoadingSounds(false);
		} else {
			closeModal("soundConfig");
		}
	});

	return (
		<Modal
			id="soundConfig"
			icon={<VolumeUpIcon />}
			title={T("soundConfigTitle")}
			onClose={() => send("CloseMenu")}
			closeButton
			loading={loadingSounds}
			modalStyling={{
				width: "50rem",
			}}
		>
			<div
				style={{
					maxHeight: "60vh",
					overflowY: "auto",
					overflowX: "hidden",
					paddingRight: "0.5rem",
				}}
			>
				<div
					style={{
						display: "flex",
						flexDirection: "column",
						gap: "0.2rem",
						padding: "0 0 1.5rem 0",
					}}
				>
					{sounds.map((sound) => (
						<SoundRow
							key={sound.name}
							name={sound.name}
							initialVolume={sound.volume}
						/>
					))}
				</div>
			</div>
		</Modal>
	);
};

export default SoundConfigMenu;
