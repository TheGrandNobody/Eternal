const { expect } = require("chai");

let owner, addr1, tt, tc, TestToken, TestContract;

describe("Functions that call transfer", function() {

  this.timeout(2000000);

  before (async function() {
    [owner, addr1] = await ethers.getSigners();
    TestToken = await ethers.getContractFactory("TestToken");
    TestContract = await ethers.getContractFactory("TestContract");
    tt = await TestToken.deploy();
    tc = await TestContract.deploy();
  });

  it("Should call transfer as the contracts and not the users", async function() {
    await tt.transfer(addr1.address, 1000);
    await tt.transfer(tc.address, 2000);
    await tc.testFunc(500, tt.address, addr1.address);
    expect(await tt.balanceOf(addr1.address)).to.equal(1000);
  });
});
