// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {RitualPredict} from "./RitualPredict.sol";

contract SchedulerDouble {
    function approveScheduler(address) external pure {}
    function schedule(bytes calldata, uint32, uint32, uint32, uint32, uint32, uint256, uint256, uint256, address) external pure returns (uint256) { return 77; }
    function cancel(uint256) external pure {}
}
contract WalletDouble {
    mapping(address => uint256) public balanceOf;
    function deposit(uint256) external payable { balanceOf[msg.sender] += msg.value; }
}
contract RegistryDouble {
    function pickServiceByCapability(uint8, bool, uint256, uint256) external pure returns (address, bool) { return (address(0xBEEF), true); }
}
contract HttpDouble {
    fallback(bytes calldata input) external returns (bytes memory) {
        string[] memory empty = new string[](0);
        bytes memory response = abi.encode(uint16(200), empty, empty, bytes('{"arrivals":61}'), "");
        return abi.encode(input, response);
    }
}
contract BrokenHttpDouble { fallback() external { revert("offline"); } }
contract JqDouble { fallback() external { assembly { mstore(0, 61) return(0, 32) } } }

contract CipherBookTest is Test {
    address constant SCHEDULER = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address constant WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address constant REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;
    address constant HTTP = address(0x0801);
    address constant JQ = address(0x0803);
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    RitualPredict market;

    function setUp() public {
        vm.etch(SCHEDULER, address(new SchedulerDouble()).code);
        vm.etch(WALLET, address(new WalletDouble()).code);
        vm.etch(REGISTRY, address(new RegistryDouble()).code);
        vm.etch(HTTP, address(new HttpDouble()).code);
        vm.etch(JQ, address(new JqDouble()).code);
        market = new RitualPredict(1000);
        vm.deal(alice, 10 ether); vm.deal(bob, 10 ether);
    }

    function params() internal pure returns (RitualPredict.NewMarket memory) {
        return RitualPredict.NewMarket("Will metro arrivals exceed 60?", "https://data.example.test/transit", ".arrivals", 60, RitualPredict.Comparator.GTE, 30, 20, 15);
    }
    function create() internal returns (uint256) { return market.createMarket{value: 0.02 ether}(params()); }
    function seal(uint256 id, address user, bool side, bytes32 salt, uint256 amount) internal {
        bytes32 commitment = market.makeCommitment(id, user, side, salt);
        vm.prank(user); market.commitPosition{value: amount}(id, commitment);
    }
    function advance(uint256 blockNumber) internal { vm.roll(blockNumber); }

    function test_CreateBooksThreePhaseScheduleAndFunding() public {
        uint256 id = create(); RitualPredict.Market memory m = market.getMarket(id);
        assertEq(m.scheduleId, 77); assertGt(m.commitEndBlock, block.number);
        assertGt(m.revealEndBlock, m.commitEndBlock); assertGt(m.resolveBlock, m.revealEndBlock);
        assertEq(WalletDouble(WALLET).balanceOf(address(market)), 0.02 ether);
    }

    function test_CommitmentDoesNotExposeSideAndDuplicateIsRejected() public {
        uint256 id = create(); bytes32 salt = keccak256("train-17"); seal(id, alice, true, salt, 1 ether);
        (bytes32 stored, uint256 amount, bool revealed,) = market.positions(id, alice);
        assertEq(stored, market.makeCommitment(id, alice, true, salt)); assertEq(amount, 1 ether); assertFalse(revealed);
        vm.prank(alice); vm.expectRevert(RitualPredict.PositionExists.selector); market.commitPosition{value: 1 ether}(id, bytes32(uint256(9)));
    }

    function test_RevealChecksPhaseSideAndSalt() public {
        uint256 id = create(); bytes32 salt = keccak256("private-salt"); seal(id, alice, true, salt, 1 ether);
        vm.prank(alice); vm.expectRevert(RitualPredict.RevealNotOpen.selector); market.revealPosition(id, true, salt);
        RitualPredict.Market memory m = market.getMarket(id); advance(m.commitEndBlock);
        vm.prank(alice); vm.expectRevert(RitualPredict.InvalidReveal.selector); market.revealPosition(id, false, salt);
        vm.prank(alice); market.revealPosition(id, true, salt); assertEq(market.yesStake(id, alice), 1 ether);
    }

    function test_UnrevealedPositionCanBeReclaimed() public {
        uint256 id = create(); seal(id, alice, true, keccak256("forgotten"), 1 ether);
        RitualPredict.Market memory m = market.getMarket(id); advance(m.revealEndBlock);
        uint256 before = alice.balance; vm.prank(alice); market.reclaimUnrevealed(id); assertEq(alice.balance, before + 1 ether);
    }

    function test_TwoSidedMarketResolvesAndPaysWinner() public {
        uint256 id = create(); bytes32 a = keccak256("a"); bytes32 b = keccak256("b");
        seal(id, alice, true, a, 1 ether); seal(id, bob, false, b, 2 ether);
        RitualPredict.Market memory m = market.getMarket(id); advance(m.commitEndBlock);
        vm.prank(alice); market.revealPosition(id, true, a); vm.prank(bob); market.revealPosition(id, false, b);
        advance(m.resolveBlock); vm.prank(SCHEDULER); market.onScheduledResolve(0, id);
        m = market.getMarket(id); assertEq(uint8(m.state), uint8(RitualPredict.MarketState.Resolved)); assertEq(uint8(m.outcome), uint8(RitualPredict.Outcome.Yes));
        uint256 before = alice.balance; vm.prank(alice); market.claimWinnings(id); assertEq(alice.balance, before + 3 ether);
    }

    function test_OneSidedRevealInvalidatesAndRefunds() public {
        uint256 id = create(); bytes32 salt = keccak256("only-side"); seal(id, alice, true, salt, 1 ether);
        RitualPredict.Market memory m = market.getMarket(id); advance(m.commitEndBlock); vm.prank(alice); market.revealPosition(id, true, salt);
        advance(m.resolveBlock); vm.prank(SCHEDULER); market.onScheduledResolve(0, id);
        m = market.getMarket(id); assertEq(uint8(m.state), uint8(RitualPredict.MarketState.Invalid));
        uint256 before = alice.balance; vm.prank(alice); market.claimRefund(id); assertEq(alice.balance, before + 1 ether);
    }

    function test_ThreeOracleFailuresBecomeRefundable() public {
        uint256 id = create(); bytes32 a = keccak256("aa"); bytes32 b = keccak256("bb");
        seal(id, alice, true, a, 1 ether); seal(id, bob, false, b, 1 ether);
        RitualPredict.Market memory m = market.getMarket(id); advance(m.commitEndBlock);
        vm.prank(alice); market.revealPosition(id, true, a); vm.prank(bob); market.revealPosition(id, false, b);
        vm.etch(HTTP, address(new BrokenHttpDouble()).code); advance(m.resolveBlock);
        for (uint256 i; i < 3; i++) { vm.prank(SCHEDULER); market.onScheduledResolve(i, id); }
        m = market.getMarket(id); assertEq(uint8(m.state), uint8(RitualPredict.MarketState.Invalid)); assertEq(m.attempts, 3);
    }

    function test_AnyoneCanExpireAnAbandonedMarket() public {
        uint256 id = create(); RitualPredict.Market memory m = market.getMarket(id);
        advance(uint256(m.resolveBlock) + market.RETRY_INTERVAL_BLOCKS() * market.MAX_ATTEMPTS() + market.SCHEDULER_TTL_BLOCKS() + 1);
        vm.prank(bob); market.expireMarket(id); m = market.getMarket(id); assertEq(uint8(m.state), uint8(RitualPredict.MarketState.Invalid));
    }
}
