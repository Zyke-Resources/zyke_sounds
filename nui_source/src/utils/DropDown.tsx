import { ButtonBase } from "@mui/material";
import { Fragment, useEffect, useState, useRef, ReactNode } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { useClickOutside } from "@mantine/hooks";
import { Box, OptionalPortal, Radio, Checkbox as MantineCheckbox } from "@mantine/core";

const itemHeight = 2.5;
const inputHeight = 5.0;
const dividerHeight = 0.1;
const dividerMarginTop = 0.4;
const dividerMarginBottom = 0.4;

// The data for the item that is passed in
export interface DropDownItemData {
    label: string;
    name: string;
    icon?: ReactNode | ((data: { style: React.CSSProperties }) => ReactNode);
    radioButton?: boolean;
    checkBox?: boolean;
    onClick?: () => void;
    subMenu?: DropDownItemType[]; // Submenu items
    disabled?: boolean; // Add disabled property
}

interface DropDownTitleData {
    label: string;
    isTitle: true;
    icon?: ReactNode | ((data: { style: React.CSSProperties }) => ReactNode);
}

interface DropDownInput {
    inputComponent: ReactNode;
}

export type DropDownItemType =
    | DropDownItemData
    | DropDownTitleData
    | DropDownInput;

// The item data & props to construct it in the dropdown menu
interface DropDownItem {
    isTitle?: boolean;
    hoverIdx: number | null;
    setHoverIdx: (num: number | null) => void;
    idx: number;
    label: string;
    icon?: ReactNode | ((data: { style: React.CSSProperties }) => ReactNode);
    onClick?: (args: any) => void;
    closeOnClick?: boolean;
    closeDropDown: () => void;
    disabled?: boolean;
    itemComponent?: (item: any) => ReactNode;
    selected?: boolean;
    radioButton?: boolean;
    checkBox?: boolean;
    menuId: string;
    item: DropDownItemType;
    globalOnClick?: (name: string, idx: number) => void;
    items?: DropDownItemType[]; // Pass the whole item object to the item component
}

interface DropDownProps {
    open: boolean;
    setOpen: (state: boolean) => void;
    title?: string;
    icon?: ReactNode | ((data: { style: React.CSSProperties }) => ReactNode);
    items: DropDownItemType[];
    styling?: React.CSSProperties;
    children?: ReactNode;
    onClick?: (name: string, idx: number) => void;
    closeOnClick?: boolean;
    position?:
    | "left-up"
    | "left"
    | "bottom"
    | "bottom-right"
    | "right"
    | "right-up";
    itemComponent?: (item: any) => ReactNode;
    useClickPosition?: boolean; // Open the dropdown at the mouse position
}

const getPosStyling = (dimensions: {
    menu: { height: number; width: number };
    child: { height: number; width: number };
}) => {
    let middle = dimensions.menu.width / 2 - dimensions.child.width / 2;
    if (middle > 0) {
        middle = -middle;
    } else {
        middle = 0 + -middle / 2;
    }

    return {
        ["left-up"]: {
            translateX: "calc(-100% - 0.5rem)",
            translateY: `calc(-${dimensions.menu.height}rem + ${dimensions.child.height}rem)`,
        },
        ["left"]: {
            translateX: "calc(-100% - 0.5rem)",
        },
        ["bottom"]: {
            translateY: "3rem",
            translateX: `${middle}rem`,
        },
        ["bottom-right"]: {
            translateY: "3.5rem",
        },
        ["right"]: {
            translateX: `calc(${dimensions.child.width}rem + 0.5rem)`,
        },
        ["right-up"]: {
            translateX: `calc(${dimensions.child.width}rem + 0.5rem)`,
            translateY: `calc(-${dimensions.menu.height}rem + ${dimensions.child.height}rem)`,
        },
    };
};

const DropDown: React.FC<DropDownProps> = ({
    open,
    setOpen,
    title,
    icon,
    items,
    styling,
    children,
    onClick: globalOnClick,
    closeOnClick,
    position = "left",
    itemComponent,
    useClickPosition = false,
}) => {
    const generateMenuId = () =>
        `dropdown-${Math.random().toString(36).slice(2, 11)}`;
    const [menuId] = useState(generateMenuId);

    const ref = useClickOutside(() => {
        if (open) setOpen(false);
    });

    const prevHoverIdx = useRef<number | null>(null);
    const [hoverIdx, setHoverIdx] = useState<number | null>(null);

    const childRef = useRef<HTMLDivElement>(null);
    const [dimensions, setDimensions] = useState({
        menu: { height: 0, width: 0 },
        child: { height: 0, width: 0 },
    });

    // Disable the positioning animation for the hover box if you are not hovering over an item
    // This is to prevent weird behavior making the hover box jump around when you hover different parts when hovering outside in between
    useEffect(() => {
        prevHoverIdx.current = hoverIdx;
    }, [hoverIdx]);

    useEffect(() => {
        if (childRef.current) {
            const dimensions = childRef.current.getBoundingClientRect();

            setDimensions((prev) => ({
                ...prev,
                child: {
                    height: dimensions.height / 10,
                    width: dimensions.width / 10,
                },
            }));
        }
    }, [children]);

    useEffect(() => {
        setHoverIdx(null);

        if (!open) return;

        const parent = document.getElementById(menuId);
        if (parent) {
            setDimensions((prev) => ({
                ...prev,
                menu: {
                    height: parent.offsetHeight / 10,
                    width: parent.offsetWidth / 10,
                },
            }));
        }
    }, [open]);

    const posStyling = getPosStyling(dimensions);

    // Add the title at the top
    if (title) {
        items = [{ label: title, icon: icon, isTitle: true }, ...items];
    }

    const [clickPos, setClickPos] = useState<{ x: number; y: number } | null>(
        null
    );

    return (
        <>
            <OptionalPortal withinPortal={useClickPosition}>
                <div
                    ref={ref}
                    style={{
                        position: "relative",
                    }}
                >
                    <AnimatePresence>
                        {open && (
                            <motion.div
                                id={menuId}
                                initial={{ opacity: 0, y: -10 }}
                                animate={{ opacity: 1, y: 0 }}
                                exit={{ opacity: 0, y: -10 }}
                                // initial={{ opacity: 0, y: -5 }}
                                // animate={{ opacity: 1, y: 5 }}
                                // exit={{ opacity: 0, y: -5 }}
                                style={{
                                    // width: "100%",
                                    boxSizing: "border-box",
                                    position: "fixed", // Sometimes needs to be set as absolute through styling
                                    background: "rgba(var(--dark), 1.0)",
                                    borderRadius: "var(--lborderRadius)",
                                    boxShadow: "0 0 5px rgba(0, 0, 0, 0.5)",
                                    border: "1px solid rgb(var(--grey3))",
                                    zIndex: 10000,
                                    cursor: "default",
                                    pointerEvents: "none",

                                    ...(useClickPosition && clickPos
                                        ? {
                                            position: "fixed",
                                            left: `${clickPos.x + 15}px`,
                                            top: `${clickPos.y - 8}px`,
                                            translateX: "0",
                                            translateY: "0",
                                        }
                                        : posStyling[position]),
                                    ...styling,
                                }}
                            >
                                <div
                                    className="item-list"
                                    style={{
                                        position: "relative",
                                        padding: "0.4rem",
                                        boxSizing: "border-box",
                                    }}
                                >
                                    <HoverBox
                                        menuId={menuId}
                                        hoverIdx={hoverIdx}
                                        items={items}
                                        prevHoverIdx={prevHoverIdx.current}
                                    />

                                    <ItemList
                                        menuId={menuId}
                                        items={items}
                                        hoverIdx={hoverIdx}
                                        setHoverIdx={setHoverIdx}
                                        globalOnClick={globalOnClick}
                                        closeOnClick={closeOnClick}
                                        closeDropDown={() => setOpen(false)}
                                        itemComponent={itemComponent}
                                    />
                                </div>
                            </motion.div>
                        )}
                    </AnimatePresence>

                    {!useClickPosition && <div ref={childRef}>{children}</div>}
                </div>
            </OptionalPortal>

            {useClickPosition && (
                <div
                    ref={childRef}
                    onClick={(e) => {
                        e.stopPropagation();
                        setClickPos({
                            x: e.clientX,
                            y: e.clientY,
                        });
                    }}
                >
                    {children}
                </div>
            )}
        </>
    );
};

export default DropDown;

interface ItemListProps {
    items: DropDownItemType[];
    hoverIdx: number | null;
    setHoverIdx: (num: number | null) => void;
    closeOnClick?: boolean;
    closeDropDown: () => void;
    itemComponent?: (item: any) => ReactNode;
    menuId: string;
    globalOnClick?: (name: string, idx: number) => void;
}

const ItemList: React.FC<ItemListProps> = ({
    items,
    hoverIdx,
    setHoverIdx,
    closeOnClick,
    closeDropDown,
    itemComponent,
    menuId,
    globalOnClick,
}) => {
    return (
        <>
            {items.map((item, idx) => {
                if ("inputComponent" in item && item.inputComponent) {
                    return (
                        <Box
                            key={"input-" + idx}
                            sx={{
                                pointerEvents: "all",

                                ["& .mantine-Input-input"]: {
                                    minHeight: "2.5rem",
                                    height: "2.5rem",
                                },

                                ["& .mantine-InputWrapper-label"]: {
                                    height: "2rem",
                                    color: "rgba(var(--secText))",
                                },

                                ["& .input-root .label"]: {
                                    color: "rgba(var(--secText))",
                                },
                            }}
                            onMouseEnter={() => setHoverIdx(idx)}
                            onMouseLeave={() => setHoverIdx(null)}
                        >
                            {item.inputComponent}
                        </Box>
                    );
                } else if ("name" in item) {
                    return (
                        <Fragment key={item.name + "-" + idx}>
                            <Item
                                idx={idx}
                                item={item}
                                menuId={menuId}
                                closeOnClick={closeOnClick}
                                closeDropDown={closeDropDown}
                                hoverIdx={hoverIdx}
                                setHoverIdx={setHoverIdx}
                                itemComponent={itemComponent}
                                globalOnClick={globalOnClick}
                                items={items}
                                {...item}
                            />
                        </Fragment>
                    );
                } else if ("isTitle" in item && item.isTitle) {
                    return (
                        <Fragment key={"title" + "-" + idx}>
                            <Item
                                idx={idx}
                                item={item}
                                menuId={menuId}
                                closeOnClick={closeOnClick}
                                closeDropDown={closeDropDown}
                                hoverIdx={hoverIdx}
                                setHoverIdx={setHoverIdx}
                                itemComponent={itemComponent}
                                globalOnClick={globalOnClick}
                                items={items}
                                {...item}
                            />

                            <Divider />
                        </Fragment>
                    );
                } else {
                    return null;
                }
            })}
        </>
    );
};

const Item: React.FC<DropDownItem> = ({
    isTitle,
    hoverIdx,
    setHoverIdx,
    idx,
    label,
    icon,
    onClick,
    closeOnClick,
    closeDropDown,
    disabled,
    itemComponent,
    selected, // If the item is marked as selected, to display an extra hoverbox for it, in blue
    radioButton,
    checkBox,
    menuId,
    item, // Pass the whole item object to the item component
    globalOnClick,
    items,
}) => {
    const hasSubMenu = "subMenu" in item && item.subMenu ? true : false;
    const [subMenuOpen, setSubMenuOpen] = useState(false);

    // Determine if the item is disabled (from prop or from item object)
    const isDisabled = disabled || ("disabled" in item && item.disabled);

    const itemComp = (
        <>
            <ButtonBase
                disableRipple={hasSubMenu}
                disabled={isTitle || isDisabled}
                onClick={(args: any) => {
                    if (!("name" in item) || isDisabled) return;

                    if (closeOnClick) closeDropDown();
                    if (globalOnClick) globalOnClick(item.name, idx);
                    if (onClick) onClick(args);
                }}
                style={{
                    display: "flex",
                    justifyContent: "start",
                    alignItems: "center",
                    gap: "0.5rem",
                    padding: "var(--spadding) var(--mpadding)",
                    width: "100%",
                    height: itemHeight + "rem",
                }}
            >
                {itemComponent ? (
                    itemComponent(item)
                ) : (
                    <>
                        {radioButton !== null && radioButton !== undefined && (
                            <Radio
                                checked={radioButton ? true : false}
                                readOnly
                                color={isDisabled ? "gray" : undefined}
                            />
                        )}

                        {checkBox !== null && checkBox !== undefined && (
                            <MantineCheckbox
                                checked={checkBox ? true : false}
                                readOnly
                                color={isDisabled ? "gray" : undefined}
                                styles={{
                                    input: { cursor: "pointer" },
                                }}
                            />
                        )}

                        {icon && (
                            <ItemIcon
                                isTitle={isTitle}
                                icon={icon}
                                disabled={isDisabled}
                            />
                        )}

                        {isTitle ? (
                            <p
                                className="truncate"
                                style={{
                                    cursor: "pointer",
                                    color: "rgba(var(--secText))",
                                    fontSize: "1.3rem",
                                    fontWeight: "500",
                                }}
                            >
                                {label}
                            </p>
                        ) : (
                            <p
                                className="truncate"
                                style={{
                                    cursor: "pointer",
                                    color:
                                        isDisabled
                                            ? "rgba(var(--secText))"
                                            : "rgba(var(--text))",
                                    fontSize: "1.2rem",
                                    fontWeight: "400",
                                }}
                            >
                                {label}
                            </p>
                        )}
                    </>
                )}
            </ButtonBase>
        </>
    );

    useEffect(() => {
        if (hoverIdx !== idx) setSubMenuOpen(false);
    }, [hoverIdx]);

    return (
        <div
            style={{
                position: "relative",
                pointerEvents: "all",
            }}
            onMouseEnter={() => {
                if (!isTitle && !isDisabled) setHoverIdx(idx);

                if (hasSubMenu && !isDisabled) {
                    setSubMenuOpen(true);
                }
            }}
            onMouseLeave={() => {
                if (hasSubMenu && !isDisabled) return;

                if (!isTitle && !isDisabled) setHoverIdx(null);

                if (hasSubMenu && !isDisabled) {
                    setSubMenuOpen(false);
                }
            }}
        >
            {/* Use a ghost div to slightly extend over the border of the main component to avoid registering as not hovering */}
            <div
                style={{
                    width: subMenuOpen ? "calc(100% + 5px)" : "100%",
                    height: "100%",
                    position: "absolute",
                    top: 0,
                    left: subMenuOpen ? "5px" : "0px",
                }}
            />

            {selected && !isDisabled && (
                <HoverBox
                    menuId={menuId}
                    hoverIdx={idx}
                    selected={true}
                    items={items}
                />
            )}

            {"subMenu" in item && hasSubMenu ? (
                <DropDown
                    open={subMenuOpen}
                    setOpen={setSubMenuOpen}
                    items={item.subMenu || []}
                    styling={{
                        width: "fit-content",

                        ...(!subMenuOpen && { pointerEvents: "none" }),
                        marginTop: "-0.5rem",
                    }}
                    position="right"
                >
                    {itemComp}
                </DropDown>
            ) : (
                itemComp
            )}
        </div>
    );
};

const HoverBox: React.FC<{
    menuId: string;
    hoverIdx: number | null;
    selected?: boolean;
    items?: DropDownItemType[];
    prevHoverIdx?: number | null;
}> = ({ menuId, hoverIdx, prevHoverIdx, selected, items }) => {
    const totalDividers = document.querySelectorAll(
        "#" + menuId + " .divider"
    ).length;

    let hoveringInputComponent = false;
    if (hoverIdx !== null && items) {
        hoveringInputComponent = "inputComponent" in items[hoverIdx];
    }

    const shouldAnimateHoverBox = prevHoverIdx !== hoverIdx;

    const hoverIdxToUse = hoverIdx !== null ? hoverIdx : prevHoverIdx || 0;
    let totalHeight = 0;
    for (let i = 0; i < (hoverIdxToUse || 0); i++) {
        if (items && items[i] && (items[i] as DropDownInput).inputComponent) {
            totalHeight += inputHeight;
        } else {
            totalHeight += itemHeight;
        }
    }

    const totalDividerHeightCalc =
        dividerHeight + dividerMarginTop + dividerMarginBottom;
    const totalDividersCalc = `calc(${totalDividers} * ${totalDividerHeightCalc}rem)`;

    return (
        <motion.div
            className="hover-box"
            style={{
                width: "100%",
                height: itemHeight + "rem",
                position: "absolute",
                top: `calc(${totalHeight}rem + ${totalDividersCalc})`,
                left: 0,
                zIndex: -1,
                padding: "0 0.4rem",
                marginTop: "0.4rem",
                opacity: hoverIdx !== null && !hoveringInputComponent ? 1 : 0,
                transition: shouldAnimateHoverBox
                    ? "top 0.1s, opacity 0.2s"
                    : "opacity 0.2s, top 0s",
            }}
        >
            <div
                style={{
                    background: selected
                        ? "rgba(var(--blue2), 1.0)"
                        : "rgba(var(--grey3), 1.0)",
                    width: "calc(100% - 0.8rem)",
                    height: itemHeight + "rem",
                    borderRadius: "var(--borderRadius)",
                    scale: hoverIdx !== null ? "1" : "0.9",
                    transition: "scale 0.4s",
                }}
            />
        </motion.div>
    );
};

const Divider = () => {
    return (
        <div
            className="divider"
            style={{
                width: "100%",
                height: dividerHeight + "rem",
                background: "rgba(var(--grey3))",
                marginTop: dividerMarginTop + "rem",
                marginBottom: dividerMarginBottom + "rem",
            }}
        ></div>
    );
};

interface ItemIconProps {
    icon: ReactNode | ((data: { style: React.CSSProperties }) => ReactNode);
    disabled?: boolean;
    isTitle?: boolean;
}

const ItemIcon: React.FC<ItemIconProps> = ({ icon, disabled, isTitle }) => {
    const fill = "rgba(var(--icon))";
    const disabledFill = "rgba(var(--secIcon))";
    const fillToUse = disabled || isTitle ? disabledFill : fill;
    const marginRight = "0.25rem";

    return (
        <>
            {typeof icon === "function" ? (
                icon({
                    style: {
                        height: "1.4rem",
                        width: "1.4rem",
                        fill: fillToUse,
                        marginRight: marginRight,
                    },
                })
            ) : (
                <Box
                    sx={{
                        display: "flex",
                        justifyContent: "center",
                        alignItems: "center",
                        "& svg": {
                            height: "1.4rem",
                            width: "1.4rem",
                            fill: fillToUse,
                            marginRight: marginRight,
                        },
                    }}
                >
                    {icon}
                </Box>
            )}
        </>
    );
};
