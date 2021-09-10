const { expect } = require("chai");

describe("Test", async () => {

    it("Should emit the correct event with the correct parameters", async () => {
        const EternalFund = await ethers.getContractFactory("EternalFundV0");
        const fund = await EternalFund.deploy();
        const Test = await ethers.getContractFactory("Test");
        const test = await Test.deploy();

        await expect(fund.execute(test.address)).to.be.returned(false);

    }) 
})