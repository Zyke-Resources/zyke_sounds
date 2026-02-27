import { memo, useMemo, useState } from "react";
import { listen, send, callback } from "../utils/nui";
import { useModalContext } from "../context/ModalContext";
import { useTranslation } from "../context/Translation";
import Modal from "../utils/Modal";
import Slider from "../utils/Slider";
import DebouncedTextInput from "../utils/DebouncedTextInput";
import DropDown, { DropDownItemType } from "../utils/DropDown";
import IconButton from "../utils/IconButton";
import VolumeUpIcon from "@mui/icons-material/VolumeUp";
import SearchIcon from "@mui/icons-material/Search";
import FilterListIcon from "@mui/icons-material/FilterList";

interface SoundEntry {
	name: string;
	volume: number;
}

const SoundRow = memo(({ name, initialVolume }: { name: string; initialVolume: number }) => {
	const [volume, setVolume] = useState(initialVolume);

	return (
		<div style={{
			borderRadius: "var(--borderRadius)",
			background: "rgba(var(--dark2))",
			border: `1px solid rgba(var(--grey2))`,
			boxShadow: "0 0 3px 0 rgba(0, 0, 0, 0.3)",
			padding: "0 0.5rem 0.5rem 0.5rem",
		}}>
			<Slider
				label={name}
				displayLabel={`${volume.toFixed(2)}x`}
				value={volume}
				onChange={setVolume}
				onChangeEnd={(val) => send("SetSoundVolume", { name, volume: val })}
				min={0}
				max={2}
				step={0.05}
				rootStyle={{
					padding: "0",
				}}
			/>
		</div>
	);
});

interface PresetData {
	invoker: string;
	sounds: string[];
}

const SoundConfigMenu = () => {
	const T = useTranslation();
	const { openModal, closeModal } = useModalContext();
	const [sounds, setSounds] = useState<SoundEntry[]>([]);
	const [loadingSounds, setLoadingSounds] = useState(false);
	const [search, setSearch] = useState("");
	const [presets, setPresets] = useState<Record<string, PresetData>>({});
	const [activePreset, setActivePreset] = useState<string | null>(null);
	const [presetDropdownOpen, setPresetDropdownOpen] = useState(false);

	const presetNames = useMemo(() => Object.keys(presets), [presets]);

	const presetDropdownItems: DropDownItemType[] = useMemo(() => {
		return presetNames.map((name) => ({
			label: name,
			name: name,
			radioButton: activePreset === name,
			onClick: () => {
				setActivePreset((prev) => (prev === name ? null : name));
			},
		}));
	}, [presetNames, activePreset]);

	const filteredSounds = useMemo(() => {
		let result = sounds;

		if (activePreset && presets[activePreset]) {
			const allowed = new Set(presets[activePreset].sounds);
			result = result.filter((s) => allowed.has(s.name));
		}

		if (search) {
			const lower = search.toLowerCase();
			result = result.filter((s) => s.name.toLowerCase().includes(lower));
		}

		return result;
	}, [sounds, search, activePreset, presets]);

	listen("SetOpen", async (val: boolean) => {
		if (val) {
			setSearch("");
			setActivePreset(null);
			setPresetDropdownOpen(false);
			setLoadingSounds(true);
			openModal("soundConfig");

			const delay = (ms: number) => new Promise((res) => setTimeout(res, ms));
			const soundsPromise = callback("GetSoundsList");
			const presetsPromise = callback("GetPresets");

			await delay(200);
			setSounds((await soundsPromise) as SoundEntry[]);
			setPresets((await presetsPromise) as Record<string, PresetData>);
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
			footer={T("soundCount", [String(filteredSounds.length)])}
		>
			<div
				style={{
					display: "flex",
					alignItems: "center",
					gap: "0.5rem",
					marginBottom: "0.5rem",
				}}
			>
				<DebouncedTextInput
					value={search}
					onChange={setSearch}
					placeholder={T("searchSounds")}
					icon={<SearchIcon />}
					sx={{ flex: 1 }}
					delay={100}
				/>
				{presetNames.length > 0 && (
					<DropDown
						open={presetDropdownOpen}
						setOpen={setPresetDropdownOpen}
						items={presetDropdownItems}
						title={T("filterPresets")}
						icon={<FilterListIcon />}
						position="right"
						styling={{
							minWidth: "16rem",
						}}
					>
						<IconButton
							onClick={() => setPresetDropdownOpen((prev) => !prev)}
							color={activePreset ? "var(--blue1)" : undefined}
						>
							<FilterListIcon />
						</IconButton>
					</DropDown>
				)}
			</div>
			<div
				style={{
					maxHeight: "60vh",
					overflowY: "auto",
					overflowX: "hidden",
				}}
			>
				<div
					style={{
						display: "flex",
						flexDirection: "column",
						gap: "0.75rem",
					}}
				>
					{filteredSounds.length === 0 ? (
						<p
							style={{
								textAlign: "center",
								color: "rgba(var(--secText))",
								padding: "1.2rem 0 0.8rem 0",
								fontSize: "1.4rem",
							}}
						>
							{T("noSoundsFound")}
						</p>
					) : (
						filteredSounds.map((sound) => (
							<SoundRow
								key={sound.name}
								name={sound.name}
								initialVolume={sound.volume}
							/>
						))
					)}
				</div>
			</div>
		</Modal>
	);
};

export default SoundConfigMenu;
