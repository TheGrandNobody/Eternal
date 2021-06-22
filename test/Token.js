const { expect } = require("chai");
const { BigNumber } = require("ethers");

let owner, addr1, addr2, Token, eternal;

beforeEach(async function() {
  [owner, addr1, addr2] = await ethers.getSigners();
  Token = await ethers.getContractFactory("EternalToken");
  eternal = await Token.deploy();
})

describe("Token contract", function() {
  it("Should correctly send 2000 tokens to user1 then 1000 to user2", async function() {
    const amount = BigNumber.from(2000000000000);
    const amount1 = BigNumber.from(1000000000000);

    await eternal.transfer(addr1.address, amount);
    await eternal.connect(addr1).transfer(addr2.address, amount1);
    
    
  });
});
