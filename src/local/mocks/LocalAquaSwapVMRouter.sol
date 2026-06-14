// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { AquaSwapVMRouter } from "../../routers/AquaSwapVMRouter.sol";

contract LocalAquaSwapVMRouter is AquaSwapVMRouter {
    constructor()
        AquaSwapVMRouter(
            0x56DC3CD72f34e356f0be3d86F814457E6A8c21Af,
            0x4d6e3eAae71E7B2bD8511fB7114d5A692468cbb6,
            0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            "RiverSwap",
            "1.0.0"
        )
    { }
}
