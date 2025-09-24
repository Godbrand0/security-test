// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import  "forge-std/Test.sol";
import {StakingRewards, IERC20} from "src/stake.sol";
import {MockERC20} from "src/ERC20.sol";

contract StakingTest is Test {
    StakingRewards staking;
    MockERC20 stakingToken;
    MockERC20 rewardToken;

    address owner = makeAddr("owner");
    address bob = makeAddr("bob");
    address dso = makeAddr("dso");

    function setUp() public {
        vm.startPrank(owner);
        stakingToken = new MockERC20();
        rewardToken = new MockERC20();
        staking = new StakingRewards(address(stakingToken), address(rewardToken));
        vm.stopPrank();
    }

    function test_alwaysPass() public {
        assertEq(staking.owner(), owner, "Wrong owner set");
        assertEq(address(staking.stakingToken()), address(stakingToken), "Wrong staking token address");
        assertEq(address(staking.rewardsToken()), address(rewardToken), "Wrong reward token address");

        assertTrue(true);
    }

    function test_cannot_stake_amount0() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);

        // we are expecting a revert if we deposit/stake zero
        vm.expectRevert("amount = 0");
        staking.stake(0);
        vm.stopPrank();
    }

    function test_can_stake_successfully() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        uint256 _totalSupplyBeforeStaking = staking.totalSupply();
        staking.stake(5e18);
        assertEq(staking.balanceOf(bob), 5e18, "Amounts do not match");
        assertEq(staking.totalSupply(), _totalSupplyBeforeStaking + 5e18, "totalsupply didnt update correctly");
    }

    function  test_cannot_withdraw_amount0() public {
        vm.prank(bob);
        vm.expectRevert("amount = 0");
        staking.withdraw(0);
    }

    function test_can_withdraw_deposited_amount() public {
        test_can_stake_successfully();

        uint256 userStakebefore = staking.balanceOf(bob);
        uint256 totalSupplyBefore = staking.totalSupply();
        staking.withdraw(2e18);
        assertEq(staking.balanceOf(bob), userStakebefore - 2e18, "Balance didnt update correctly");
        assertLt(staking.totalSupply(), totalSupplyBefore, "total supply didnt update correctly");

    }

    function test_notify_Rewards() public {
        // check that it reverts if non owner tried to set duration
        vm.expectRevert("not authorized");
        staking.setRewardsDuration(1 weeks);

        // simulate owner calls setReward successfully
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        assertEq(staking.duration(), 1 weeks, "duration not updated correctly");
        // log block.timestamp
        console.log("current time", block.timestamp);
        // move time foward 
        vm.warp(block.timestamp + 200);
        // notify rewards 
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner); 
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        
        // trigger revert
        vm.expectRevert("reward rate = 0");
        staking.notifyRewardAmount(1);
    
        // trigger second revert
        vm.expectRevert("reward amount > balance");
        staking.notifyRewardAmount(200 ether);

        // trigger first type of flow success
        staking.notifyRewardAmount(100 ether);
        assertEq(staking.rewardRate(), uint256(100 ether)/uint256(1 weeks));
        assertEq(staking.finishAt(), uint256(block.timestamp) + uint256(1 weeks));
        assertEq(staking.updatedAt(), block.timestamp);
    
        // trigger setRewards distribution revert
        vm.expectRevert("reward duration not finished");
        staking.setRewardsDuration(1 weeks);
    
    }

  function test_can_get_rewards() public {
    // 1. Bob stakes
    test_can_stake_successfully();

    uint256 earnedBefore = staking.earned(bob);
    assertEq(earnedBefore, 0, "Bob should not have rewards yet");

    // 2. Fund reward distributor (owner) with tokens
    deal(address(rewardToken), owner, 100 ether);

    // 3. Owner funds the staking contract
    vm.startPrank(owner);
    rewardToken.transfer(address(staking), 100 ether);
    staking.setRewardsDuration(1 weeks);
    staking.notifyRewardAmount(100 ether);
    vm.stopPrank();

    // 4. Advance time so rewards accrue
    vm.warp(block.timestamp + 3 days);

    // 5. Bob claims rewards
    uint256 newRewardEarned = staking.earned(bob);

    // 6. Verify rewards increased
    assertGt(newRewardEarned, earnedBefore, "Rewards did not accrue");
    // assertEq(rewardToken.balanceOf(bob), newRewardEarned, "Bob did not receive reward tokens");
}


function test_can_claim_rewards() public {
    // 1. Bob stakes
    test_can_stake_successfully();

    // Initial rewards check
    uint256 earnedBefore = staking.earned(bob);
    assertEq(earnedBefore, 0, "Bob should not have rewards yet");

    // 2. Fund reward distributor (owner) with tokens
    deal(address(rewardToken), owner, 100 ether);

    // 3. Owner funds the staking contract
    vm.startPrank(owner);
    rewardToken.transfer(address(staking), 100 ether);
    staking.setRewardsDuration(1 weeks);
    staking.notifyRewardAmount(100 ether);
    vm.stopPrank();

    // 4. Advance time so rewards accrue
    vm.warp(block.timestamp + 3 days);

    // 5. Bob claims rewards
    vm.startPrank(bob);
    staking.getReward(); // assuming this is the claim function
    vm.stopPrank();

    // 6. Verify Bob received tokens and rewards reset
    uint256 bobBalance = rewardToken.balanceOf(bob);
    assertGt(bobBalance, 0, "Bob did not receive reward tokens");

    uint256 earnedAfter = staking.earned(bob);
    assertEq(earnedAfter, 0, "Rewards should reset after claiming");
}

function test_cannot_claim_zero_rewards() public {
    // 1. Bob stakes but no rewards have been funded or accrued
    test_can_stake_successfully();

    // Ensure earned rewards are 0
    uint256 earned = staking.earned(bob);
    assertEq(earned, 0, "Bob should have 0 rewards before claiming");

    // 2. Bob tries to claim rewards
    vm.startPrank(bob);
    staking.getReward(); // should not transfer anything
    vm.stopPrank();

    // 3. Verify Bob did not receive any tokens
    uint256 bobBalance = rewardToken.balanceOf(bob);
    assertEq(bobBalance, 0, "Bob should not receive tokens when claiming 0 rewards");
}
function test_reward_per_token_not_0() public {
    // 1. Bob stakes tokens
    test_can_stake_successfully();

    // 2. Fund reward distributor (owner) with reward tokens
    deal(address(rewardToken), owner, 200 ether);

    // 3. Owner transfers rewards to staking contract and sets duration
    vm.startPrank(owner);
    rewardToken.transfer(address(staking), 100 ether);
    staking.setRewardsDuration(1 weeks);

    // 4. Notify staking contract of reward amount
    staking.notifyRewardAmount(100 ether);
    vm.stopPrank();

    // 5. Advance time so rewards accumulate
    vm.warp(block.timestamp + 5 days);

    // 6. Fetch reward rate and reward per token stored
    uint256 rewardRate   = staking.rewardRate();
    uint256 rewardStored = staking.rewardPerTokenStored();
    uint256 rewardPerToken = staking.rewardPerToken();

    // 7. Assert values make sense
    assertGt(rewardRate, 0, "reward rate should be greater than 0");
    // assertGt(rewardStored, 0, "rewardPerTokenStored should be greater than 0");
   assertGt(rewardPerToken, 0, "rewardPerToken should be greater than 0");
}
function test_setRewardsDuration_revertIfNotOwner() public {
    // Try calling as Bob
    vm.startPrank(bob);
    vm.expectRevert("not authorized");
    staking.setRewardsDuration(2 weeks);
    vm.stopPrank();
}

function test_setRewardsDuration_success() public {
    // Fund the staking contract so it has rewards
    deal(address(rewardToken), owner, 100 ether);

    vm.startPrank(owner);

    // First set the reward duration (avoid div by zero)
    staking.setRewardsDuration(1 weeks);

    // Transfer rewards and notify
    rewardToken.transfer(address(staking), 100 ether);
    staking.notifyRewardAmount(100 ether);
    vm.stopPrank();

    // Fast-forward past the reward period
    vm.warp(block.timestamp + 8 days);

    // Owner sets new duration successfully
    vm.startPrank(owner);
    staking.setRewardsDuration(2 weeks);
    vm.stopPrank();

    assertEq(staking.duration(), 2 weeks, "duration not updated correctly");
}


function test_notifyRewardAmount_topUpRewards() public {
    deal(address(rewardToken), owner, 200 ether);

    vm.startPrank(owner);
    staking.setRewardsDuration(1 weeks);
    rewardToken.transfer(address(staking), 200 ether);

    // First notify
    staking.notifyRewardAmount(100 ether);
    uint256 rateBefore = staking.rewardRate();

    // Halfway through
    vm.warp(block.timestamp + 3 days);

    // Top up again
    staking.notifyRewardAmount(100 ether);

    assertGt(staking.rewardRate(), rateBefore, "rewardRate not increased after top-up");
    vm.stopPrank();
}



function test_setRewardsDuration_revertIfRewardsActive() public {
    deal(address(rewardToken), owner, 100 ether);

    vm.startPrank(owner);
    staking.setRewardsDuration(1 weeks);
    rewardToken.transfer(address(staking), 100 ether);
    staking.notifyRewardAmount(100 ether);

    // Warp halfway into reward period
    vm.warp(block.timestamp + 3 days);

    // Should revert since finishAt > block.timestamp
    vm.expectRevert("reward duration not finished");
    staking.setRewardsDuration(2 weeks);
    vm.stopPrank();
}



}