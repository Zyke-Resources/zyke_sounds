import { Box, Slider as MantineSlider } from "@mantine/core";
import { GrTooltip } from "react-icons/gr";
import Tooltip from "./Tooltip";
import { useRef } from "react";

import "../styling/slider.css";

export interface SliderProps {
	label?: string;
	description?: string;
	icon?: React.ReactNode;
	displayLabel?: string;
	displayLabelAlwaysOn?: boolean;
	value: number;
	onChange: (e: number) => void;
	onChangeEnd?: (e: number) => void;
	error?: string;
	disabled?: boolean;
	rootStyle?: React.CSSProperties;
	style?: React.CSSProperties;
	min?: number;
	max: number;
	step?: number;
	precision?: number;
	marks?: { value: number; label: string }[];
	tooltip?: string;
	contained?: boolean;
}

const Slider: React.FC<SliderProps> = ({
	label,
	description,
	icon,
	displayLabel,
	displayLabelAlwaysOn,
	value,
	onChange,
	onChangeEnd,
	disabled,
	rootStyle,
	style,
	min,
	max,
	step,
	marks,
	tooltip,
	contained,
}) => {
	const prevVal = useRef(value);

	const handleChange = (newValue: number) => {
		if (newValue !== prevVal.current) {
			prevVal.current = newValue;
			onChange(newValue);
		}
	};

	return (
		<Box className="slider-root" style={rootStyle} data-disabled={disabled}>
			{(label || description) && (
				<Box
					style={{
						marginBottom: "0.4rem",
						display: "flex",
						alignItems: "end",
						justifyContent: "space-between",
						height: "1.95rem",
					}}
				>
					<div>
						<p
							style={{
								fontSize: "1.3rem",
								color: "rgba(var(--text))",
							}}
						>
							{label}
						</p>
						<p
							style={{
								fontSize: "1.1rem",
								color: "rgba(var(--secText))",
								marginTop: "-0.3rem",
								lineHeight: "1",
							}}
						>
							{description}
						</p>
					</div>
					{tooltip && (
						<Tooltip label={tooltip} position="top" withArrow>
							<GrTooltip className="tooltip-icon" />
						</Tooltip>
					)}
				</Box>
			)}
			{contained ? (
				<Box className="slider-box">
					{icon && (
						<Box
							sx={{
								display: "flex",
								alignItems: "center",
								justifyContent: "center",
								marginRight: "0.25rem",
							}}
						>
							{icon}
						</Box>
					)}
					<MantineSlider
						label={displayLabel}
						labelAlwaysOn={displayLabelAlwaysOn}
						marks={marks}
						style={{
							width: "100%",
							...style,
						}}
						min={min ?? 0.0}
						max={max}
						step={step}
						value={value}
						onChange={handleChange}
						onChangeEnd={onChangeEnd}
						disabled={disabled}
					/>
				</Box>
			) : (
				<MantineSlider
					label={displayLabel}
					labelAlwaysOn={displayLabelAlwaysOn}
					marks={marks}
					style={{
						width: "100%",
						...style,
					}}
					min={min ?? 0.0}
					max={max}
					step={step}
					value={value}
					onChange={handleChange}
					onChangeEnd={onChangeEnd}
					disabled={disabled}
				/>
			)}
		</Box>
	);
};

export default Slider;
