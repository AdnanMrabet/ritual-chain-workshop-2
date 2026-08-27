// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {RitualChain, IScheduler, IRitualWallet, ITEEServiceRegistry} from "./ritual/RitualChain.sol";

/// @title CipherBook
/// @notice Self-resolving markets with positions sealed until a reveal phase.
contract RitualPredict {
    enum MarketState { Commit, Reveal, Resolving, Resolved, Invalid }
    enum Comparator { GT, GTE, LT, LTE }
    enum Outcome { Unresolved, Yes, No }

    struct Market {
        uint256 id; address creator; string question; string oracleUrl; string jsonPath;
        uint256 target; Comparator comparator; uint64 commitEndBlock; uint64 revealEndBlock;
        uint64 resolveBlock; uint256 scheduleId; uint256 totalYes; uint256 totalNo;
        MarketState state; Outcome outcome; uint8 attempts; uint256 observedValue; string invalidReason;
    }
    struct NewMarket {
        string question; string oracleUrl; string jsonPath; uint256 target; Comparator comparator;
        uint256 commitSeconds; uint256 revealSeconds; uint256 resolveDelaySeconds;
    }
    struct SealedPosition { bytes32 commitment; uint256 amount; bool revealed; bool reclaimed; }

    uint32 public constant MAX_ATTEMPTS = 3;
    uint32 public constant RETRY_INTERVAL_BLOCKS = 200;
    uint32 public constant RESOLVE_GAS_LIMIT = 2_000_000;
    uint32 public constant SCHEDULER_TTL_BLOCKS = 150;
    uint256 public constant HTTP_TTL_BLOCKS = 100;
    uint256 public constant EXECUTOR_PROBES = 8;
    uint256 public constant MIN_MAX_FEE_PER_GAS = 1 gwei;
    uint256 public constant MIN_PHASE_SECONDS = 15;
    uint256 public constant MAX_MARKET_SECONDS = 1 days;

    uint256 public immutable blockTimeMs;
    uint256 public marketCount;
    mapping(uint256 => Market) private _markets;
    mapping(uint256 => mapping(address => SealedPosition)) public positions;
    mapping(uint256 => mapping(address => uint256)) public yesStake;
    mapping(uint256 => mapping(address => uint256)) public noStake;
    mapping(uint256 => mapping(address => bool)) public settled;

    event MarketCreated(uint256 indexed marketId, address indexed creator, string question, uint64 commitEndBlock, uint64 revealEndBlock, uint64 resolveBlock, uint256 scheduleId);
    event ResolutionRuleSet(uint256 indexed marketId, string oracleUrl, string jsonPath, uint256 target, Comparator comparator);
    event PositionCommitted(uint256 indexed marketId, address indexed bettor, bytes32 commitment, uint256 amount);
    event PositionRevealed(uint256 indexed marketId, address indexed bettor, bool isYes, uint256 amount);
    event UnrevealedReclaimed(uint256 indexed marketId, address indexed bettor, uint256 amount);
    event ResolutionAttempted(uint256 indexed marketId, uint8 attempt, address executor);
    event ResolutionFailed(uint256 indexed marketId, uint8 attempt, string reason);
    event MarketResolved(uint256 indexed marketId, Outcome outcome, uint256 observedValue);
    event MarketInvalidated(uint256 indexed marketId, string reason);
    event WinningsClaimed(uint256 indexed marketId, address indexed claimant, uint256 amount);
    event StakeRefunded(uint256 indexed marketId, address indexed claimant, uint256 amount);

    error UnknownMarket(); error OnlyScheduler(); error CommitClosed(); error RevealClosed();
    error RevealNotOpen(); error ZeroStake(); error PositionExists(); error NoPosition();
    error InvalidReveal(); error AlreadyRevealed(); error NotResolved(); error NotInvalid();
    error NothingToClaim(); error AlreadySettled(); error BadDuration(); error EmptyString();
    error TransferFailed(); error TooEarly();

    constructor(uint256 blockTimeMs_) {
        if (blockTimeMs_ == 0) revert BadDuration();
        blockTimeMs = blockTimeMs_;
        IScheduler(RitualChain.SCHEDULER).approveScheduler(RitualChain.SCHEDULER);
    }

    function createMarket(NewMarket calldata p) external payable returns (uint256 marketId) {
        if (bytes(p.question).length == 0 || bytes(p.oracleUrl).length == 0 || bytes(p.jsonPath).length == 0) revert EmptyString();
        uint256 duration = p.commitSeconds + p.revealSeconds + p.resolveDelaySeconds;
        if (p.commitSeconds < MIN_PHASE_SECONDS || p.revealSeconds < MIN_PHASE_SECONDS || p.resolveDelaySeconds < MIN_PHASE_SECONDS || duration > MAX_MARKET_SECONDS) revert BadDuration();
        marketId = ++marketCount;
        uint64 commitEnd = uint64(block.number + _secondsToBlocks(p.commitSeconds));
        uint64 revealEnd = uint64(commitEnd + _secondsToBlocks(p.revealSeconds));
        uint64 resolveAt = uint64(revealEnd + _secondsToBlocks(p.resolveDelaySeconds));
        if (msg.value > 0) IRitualWallet(RitualChain.RITUAL_WALLET).deposit{value: msg.value}(uint256(resolveAt - block.number) + SCHEDULER_TTL_BLOCKS + RETRY_INTERVAL_BLOCKS * MAX_ATTEMPTS);
        uint256 scheduleId = _scheduleResolution(marketId, resolveAt);
        _markets[marketId] = Market(marketId, msg.sender, p.question, p.oracleUrl, p.jsonPath, p.target, p.comparator, commitEnd, revealEnd, resolveAt, scheduleId, 0, 0, MarketState.Commit, Outcome.Unresolved, 0, 0, "");
        emit MarketCreated(marketId, msg.sender, p.question, commitEnd, revealEnd, resolveAt, scheduleId);
        emit ResolutionRuleSet(marketId, p.oracleUrl, p.jsonPath, p.target, p.comparator);
    }

    function makeCommitment(uint256 marketId, address bettor, bool isYes, bytes32 salt) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(marketId, bettor, isYes, salt));
    }

    function commitPosition(uint256 marketId, bytes32 commitment) external payable {
        Market storage m = _market(marketId);
        if (block.number >= m.commitEndBlock) revert CommitClosed();
        if (msg.value == 0) revert ZeroStake();
        if (commitment == bytes32(0)) revert InvalidReveal();
        if (positions[marketId][msg.sender].commitment != bytes32(0)) revert PositionExists();
        positions[marketId][msg.sender] = SealedPosition(commitment, msg.value, false, false);
        emit PositionCommitted(marketId, msg.sender, commitment, msg.value);
    }

    function revealPosition(uint256 marketId, bool isYes, bytes32 salt) external {
        Market storage m = _market(marketId);
        if (block.number < m.commitEndBlock) revert RevealNotOpen();
        if (block.number >= m.revealEndBlock) revert RevealClosed();
        SealedPosition storage p = positions[marketId][msg.sender];
        if (p.commitment == bytes32(0)) revert NoPosition();
        if (p.revealed) revert AlreadyRevealed();
        if (p.commitment != makeCommitment(marketId, msg.sender, isYes, salt)) revert InvalidReveal();
        p.revealed = true;
        if (isYes) { yesStake[marketId][msg.sender] = p.amount; m.totalYes += p.amount; }
        else { noStake[marketId][msg.sender] = p.amount; m.totalNo += p.amount; }
        emit PositionRevealed(marketId, msg.sender, isYes, p.amount);
    }

    function reclaimUnrevealed(uint256 marketId) external {
        Market storage m = _market(marketId);
        if (block.number < m.revealEndBlock) revert TooEarly();
        SealedPosition storage p = positions[marketId][msg.sender];
        if (p.commitment == bytes32(0)) revert NoPosition();
        if (p.revealed || p.reclaimed) revert NothingToClaim();
        p.reclaimed = true;
        emit UnrevealedReclaimed(marketId, msg.sender, p.amount);
        _pay(msg.sender, p.amount);
    }

    function onScheduledResolve(uint256 executionIndex, uint256 marketId) external {
        if (msg.sender != RitualChain.SCHEDULER) revert OnlyScheduler();
        Market storage m = _market(marketId);
        if (m.state == MarketState.Resolved || m.state == MarketState.Invalid || block.number < m.resolveBlock) return;
        if (m.totalYes == 0 || m.totalNo == 0) { _invalidate(m, marketId, "two revealed sides required"); return; }
        uint8 attempt = uint8(executionIndex + 1);
        if (attempt <= m.attempts || attempt > MAX_ATTEMPTS) return;
        m.attempts = attempt; m.state = MarketState.Resolving;
        address executor = _pickExecutor(marketId, executionIndex);
        emit ResolutionAttempted(marketId, attempt, executor);
        if (executor == address(0)) { _fail(m, marketId, attempt, "no HTTP executor"); return; }
        (bool ok, uint256 observed, string memory reason) = _readOracle(m, executor);
        if (!ok) { _fail(m, marketId, attempt, reason); return; }
        m.observedValue = observed;
        m.outcome = _compare(observed, m.target, m.comparator) ? Outcome.Yes : Outcome.No;
        m.state = MarketState.Resolved;
        emit MarketResolved(marketId, m.outcome, observed);
    }

    function expireMarket(uint256 marketId) external {
        Market storage m = _market(marketId);
        uint256 deadline = uint256(m.resolveBlock) + RETRY_INTERVAL_BLOCKS * MAX_ATTEMPTS + SCHEDULER_TTL_BLOCKS;
        if (block.number <= deadline || m.state == MarketState.Resolved || m.state == MarketState.Invalid) revert TooEarly();
        _invalidate(m, marketId, "resolution window expired");
    }

    function _fail(Market storage m, uint256 marketId, uint8 attempt, string memory reason) private {
        emit ResolutionFailed(marketId, attempt, reason);
        if (attempt >= MAX_ATTEMPTS) _invalidate(m, marketId, reason);
    }
    function _invalidate(Market storage m, uint256 marketId, string memory reason) private {
        m.state = MarketState.Invalid; m.invalidReason = reason; emit MarketInvalidated(marketId, reason);
    }

    function claimWinnings(uint256 marketId) external {
        Market storage m = _market(marketId);
        if (m.state != MarketState.Resolved) revert NotResolved();
        if (settled[marketId][msg.sender]) revert AlreadySettled();
        uint256 payout = _payout(m, marketId, msg.sender);
        if (payout == 0) revert NothingToClaim();
        settled[marketId][msg.sender] = true;
        emit WinningsClaimed(marketId, msg.sender, payout); _pay(msg.sender, payout);
    }
    function claimRefund(uint256 marketId) external {
        Market storage m = _market(marketId);
        if (m.state != MarketState.Invalid) revert NotInvalid();
        if (settled[marketId][msg.sender]) revert AlreadySettled();
        uint256 amount = yesStake[marketId][msg.sender] + noStake[marketId][msg.sender];
        if (amount == 0) revert NothingToClaim();
        settled[marketId][msg.sender] = true;
        emit StakeRefunded(marketId, msg.sender, amount); _pay(msg.sender, amount);
    }
    function _payout(Market storage m, uint256 marketId, address account) private view returns (uint256) {
        bool yesWon = m.outcome == Outcome.Yes;
        uint256 stake = yesWon ? yesStake[marketId][account] : noStake[marketId][account];
        uint256 winningPool = yesWon ? m.totalYes : m.totalNo;
        return stake == 0 || winningPool == 0 ? 0 : stake * (m.totalYes + m.totalNo) / winningPool;
    }

    function getMarket(uint256 marketId) public view returns (Market memory m) {
        m = _markets[marketId]; if (m.commitEndBlock == 0) revert UnknownMarket();
        if (m.state == MarketState.Commit && block.number >= m.commitEndBlock) m.state = MarketState.Reveal;
        if (m.state == MarketState.Reveal && block.number >= m.revealEndBlock) m.state = MarketState.Resolving;
    }
    function getMarkets() external view returns (Market[] memory all) {
        all = new Market[](marketCount); for (uint256 i; i < marketCount; i++) all[i] = getMarket(marketCount - i);
    }
    function positionOf(uint256 marketId, address account) external view returns (SealedPosition memory p, uint256 claimable) {
        p = positions[marketId][account]; Market storage m = _market(marketId);
        if (p.reclaimed || settled[marketId][account]) return (p, 0);
        if (!p.revealed && block.number >= m.revealEndBlock) return (p, p.amount);
        if (m.state == MarketState.Resolved) claimable = _payout(m, marketId, account);
        else if (m.state == MarketState.Invalid) claimable = yesStake[marketId][account] + noStake[marketId][account];
    }

    function fundExecution(uint256 lockDurationBlocks) external payable {
        if (msg.value == 0) revert ZeroStake(); IRitualWallet(RitualChain.RITUAL_WALLET).deposit{value: msg.value}(lockDurationBlocks);
    }
    function executionBalance() external view returns (uint256) { return IRitualWallet(RitualChain.RITUAL_WALLET).balanceOf(address(this)); }

    function _readOracle(Market storage m, address executor) private returns (bool, uint256, string memory) {
        bytes[] memory emptyBytes = new bytes[](0); string[] memory emptyStrings = new string[](0);
        bytes memory input = abi.encode(executor, emptyBytes, HTTP_TTL_BLOCKS, emptyBytes, bytes(""), m.oracleUrl, RitualChain.HTTP_GET, emptyStrings, emptyStrings, bytes(""), uint256(0), uint8(0), false);
        (bool called, bytes memory raw) = RitualChain.HTTP_PRECOMPILE.call(input);
        if (!called) return (false, 0, "HTTP precompile reverted");
        try this.decodeHttpResponse(raw) returns (uint16 status, bytes memory body, string memory err) {
            if (status < 200 || status >= 300) return (false, 0, "oracle returned non-2xx");
            if (bytes(err).length != 0) return (false, 0, err);
            (bool jqOk, uint256 value) = _jqUint(m.jsonPath, string(body));
            return jqOk ? (true, value, "") : (false, 0, "jq extraction failed");
        } catch { return (false, 0, "malformed oracle response"); }
    }
    function decodeHttpResponse(bytes calldata raw) external pure returns (uint16 status, bytes memory body, string memory errorMessage) {
        (, bytes memory actualOutput) = abi.decode(raw, (bytes, bytes)); require(actualOutput.length > 0, "async output not settled");
        (status, , , body, errorMessage) = abi.decode(actualOutput, (uint16, string[], string[], bytes, string));
    }
    function _jqUint(string memory query, string memory json) private view returns (bool, uint256) {
        (bool ok, bytes memory result) = RitualChain.JQ_PRECOMPILE.staticcall(abi.encode(query, json, RitualChain.JQ_OUT_UINT256));
        if (!ok || result.length < 32) return (false, 0); return (true, abi.decode(result, (uint256)));
    }
    function _pickExecutor(uint256 marketId, uint256 executionIndex) private view returns (address) {
        (address executor, bool found) = ITEEServiceRegistry(RitualChain.TEE_SERVICE_REGISTRY).pickServiceByCapability(RitualChain.CAPABILITY_HTTP_CALL, true, uint256(keccak256(abi.encode(marketId, executionIndex, block.prevrandao))), EXECUTOR_PROBES);
        return found ? executor : address(0);
    }
    function _scheduleResolution(uint256 marketId, uint64 resolveBlock) private returns (uint256) {
        return IScheduler(RitualChain.SCHEDULER).schedule(abi.encodeCall(this.onScheduledResolve, (0, marketId)), RESOLVE_GAS_LIMIT, uint32(resolveBlock), MAX_ATTEMPTS, RETRY_INTERVAL_BLOCKS, SCHEDULER_TTL_BLOCKS, MIN_MAX_FEE_PER_GAS, 0, 0, address(this));
    }
    function _market(uint256 marketId) private view returns (Market storage m) { m = _markets[marketId]; if (m.commitEndBlock == 0) revert UnknownMarket(); }
    function _compare(uint256 observed, uint256 target, Comparator comparator) private pure returns (bool) {
        if (comparator == Comparator.GT) return observed > target; if (comparator == Comparator.GTE) return observed >= target; if (comparator == Comparator.LT) return observed < target; return observed <= target;
    }
    function _secondsToBlocks(uint256 seconds_) private view returns (uint256 blocks) { blocks = seconds_ * 1000 / blockTimeMs; if (blocks == 0) blocks = 1; }
    function _pay(address to, uint256 amount) private { (bool ok,) = payable(to).call{value: amount}(""); if (!ok) revert TransferFailed(); }
    receive() external payable {}
}
