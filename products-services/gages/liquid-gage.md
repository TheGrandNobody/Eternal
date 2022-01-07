---
description: A solution to decentralized corporate short-termism.
---

# Liquid Gage

### <mark style="color:blue;">Definition</mark>

<mark style="color:purple;">Liquid gages are loyalty gages which provide call warrants for a protocol's liquidity. Thus a liquid gage also involves an entity or individual distributing an asset (</mark><mark style="color:purple;">**the distributor**</mark><mark style="color:purple;">), to another entity or individual receiving said asset (</mark><mark style="color:purple;">**the receiver**</mark><mark style="color:purple;">). The risked percentage of the distributor is always lower than that of the receiver.</mark>

### Properties

**Distributor Condition:** A threshold involving the total token supply and its yearly inflation/deflation rate.

**Receiver Condition:** Non-withdrawal of deposit

**Less **<mark style="color:red;">**Risk**</mark>**, More **<mark style="color:green;">**Reward:**</mark> A liquid gage's risk to reward is always greater than or equal to 2:1 as long as the receiver risk, $$\mu$$, is no more than twice the distributor risk, $$\gamma$$. Given a deposit $$x$$, this is shown by the calculation of the risk to reward $$R$$:

$$R = \frac{2\gamma x}{(\mu - \gamma)x} = \frac{2\gamma}{\mu - \gamma} = \frac{2\gamma}{2\gamma- \gamma} = 2$$

<mark style="color:green;">**Bonus:**</mark> A given amount of an asset is instantly available to the receiver upon activation of the gage.

<mark style="color:yellow;">**Discount:**</mark>** **<mark style="color:red;">****</mark> The receiver is able to provide liquidity using half of the asset amounts needed.

<mark style="color:orange;">**Symb**</mark><mark style="color:green;">**iosis:**</mark>** ** Loyalty gages create symbiotic relationships between any given distributor and receiver.

### <mark style="color:blue;">**Example – Decentralized Finance**</mark>

<mark style="color:purple;">Alice created a blockchain project and wants to ensure long-term liquidity provision (LP) of her token which is valued at 1 USDC. Bob wants to pool 100 tokens and 100 USDC to obtain 100 of Alice's LP tokens. However, Bob is a liquidity provider who only participates early in the project and moves on once the rewards are not high enough for him. Alice, the distributor, offers a liquid gage to Bob, the receiver.</mark>&#x20;

<mark style="color:purple;">The liquid gage warrants Bob 100 LP tokens at a 50% discount, where Bob only needs to deposit USDC or Alice's token, but not both. The parameters are set to a risk percentage of 5% for Alice, a 5.5% risk percentage for Bob and a 5% bonus of the value of the LP tokens in the form of Alice's token. The distributor condition depends on whether Alice's total token supply has increased by a threshold of 2.5%, or 25% of the token's yearly inflation rate. The receiver condition depends on whether Bob withdraws the deposited LP tokens.</mark>&#x20;

<mark style="color:purple;">As soon as the liquid gage is active, the bonus of 10 (of Alice's) token is awarded to Bob's wallet, who can freely spend it at will. If Bob withdraws his LP tokens (plus LP rewards) before Alice's total token supply has increased by 2.5%, then Bob pays Alice 5.5 LP tokens (equivalent to 11 of Alice's tokens), plus 55.5% of his LP rewards. If Alice's total token supply increases by 2.5% before Bob withdraws the 100 LP tokens deposited in the contract, then Bob receives an additional 10 tokens and 55% of the LP rewards.</mark>&#x20;

<mark style="color:purple;">To allow liquid gages, Alice can either reserve some of her token supply for liquid gages, rather than for liquidity mining incentives or setup staking for her token such that holders can provide their tokens for liquidity provision.</mark>&#x20;

{% hint style="info" %}
<mark style="color:blue;">**Alice either gains healthy long-term liquidity providers or profits.**</mark>

<mark style="color:blue;">**Bob gets to provide liquidity at a 50% discount and either gains the equivalent of 20% more LP tokens, or pays 1% more for the original LP tokens and a part of his LP-rewards.**</mark>

<mark style="color:blue;">**Loyalty gages end the short-termist relationships between Blockchain projects and liquidity providers and also remove the need for abnormally high liquidity mining incentives, while still giving complete freedom of choice and action to all stakeholders.**</mark>
{% endhint %}
