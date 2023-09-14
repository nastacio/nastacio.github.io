---
title: On Technical Debt, Margin Calls, and Ponzi Schemes
header:
  teaser: /assets/images/technical-debt/technical-cdo.png
category:
  - essay
tags:
  - technology
  - software
  - programming
  - product management
toc: true
---

_New Financial Metaphors and Debt Management Lessons for Modern Software Development_

| ![Photo of a "Wall St" street sign between 1 and 21 street](/assets/images/technical-debt/patrick-weissenberger-wallstreet-unsplash.jpg) |
|:--:|
| _"Photo by [Patrick Weissenberger](https://unsplash.com/@ricktap) on Unsplash"_ |

_“When I began the Ponzi scheme I believed it would end shortly and I would be able to extricate myself and my clients from the scheme.” — Bernard Madoff._

Software developers can be great with numbers but are usually terrible with finances.

Ward Cunningham coined the term “[technical debt](https://en.wikipedia.org/wiki/Technical_debt)” to describe a particular category of project issues. Those issues required refactoring to make it easier to work with the codebase but did not affect the final product delivered to the customer.

That was [thirty years ago](https://c2.com/doc/oopsla92.html).

It was a period populated with client-server architectures, long before Clouds and the Internet became integral parts of system runtimes.

Fast-forward to modern cloud-based architectures and a poorly organized interface is no longer a bucket of bytes inside an object file; it is a web of calls among micro-services.

The technical debt scope gradually evolved from _“internal to the development team”_ to _“not immediately detectable by the customer.”_

New paradigms demand new metaphors.

And when one needs new debt metaphors, one must turn to the financial markets. In the intervening years since the 90s, the financial industry created mind-bending accounting maneuvers to manage “leverage” — a sophisticated jargon word for risky debt.

This story introduces some of these new forms of financial debt, using them to help us recognize and manage technical debt with new perspectives.

Before getting started, we need a quick recap of a software project’s “investment” stages and how much technical debt lurks in between.

---

## The Four Stages of Investment

Systems don’t grow linearly. The codebase might, but the requirements grow in leaps across stages.

A product development organization may use a different breakdown of stages and more complete definitions for each stage. For simplicity, let’s use these four stages as context throughout the rest of the story.

1. **Prototype** or “proof of concept.” The project covers the use cases most relevant to the customers, exploring concepts that may be new to the customer or technologies that may be new to the team. It is often a learning tool rather than a precursor to the actual code in production.
2. **Product**. As the name suggests, it is something that customers can use in a production environment. The code has been methodically put through a matrix of validation tests that best matches the team’s domain knowledge. The code is accompanied by manuals, tutorials, field engineers, and a dedicated support structure.
3. **System**. The product can interoperate with other systems to cover a broader range of use cases at the customer site. For example, a product may have an internal identity provider but also support the OAuth standard for interoperability with other systems.
4. **Service.** A system does not deliver value until it is in service or operation. Operating a system requires a different set of skills and tools, which in turn requires specific features integrated into the product, such as metrics for observability purposes, autonomous capabilities for self-diagnosing, and self-tuning.

Crossing from one stage to the other incurs significant development costs. My rule of thumb for estimation, which I covered in [“How to Outperform a 10x Developer”](https://medium.com/better-programming/how-to-outperform-a-10x-developer-fa1132807934), is that you need to _apply a multiple of nearly thirty times to the initial cost of a prototype before you can have it as a service in the field_.

| ![3D cube with a teddy bear in one corner and a robot tending to a conveyor belt on the opposite corner. The dimensions of the cube are labeld: system, service, and product.](/assets/images/technical-debt/investment-stages.png) |
|:--:|
| _Prototypes may look ready for use, but it takes considerable effort to ensure they will work consistently and reliably under different conditions._ |

### Technical Debt Lesson #1: Look Beyond The Code

The most significant source of technical debt is not developers ignoring a DRY or SOLID principle here and there — those can be damaging in their own right — but customers led to believe a project is ahead of its actual development stage.

_“But why would anyone want to misrepresent the development stage of a project?”_

Economics and growth.

---

## The Investor’s Mindset: Growth Trumps Debt

[Global population growth projections](https://en.wikipedia.org/wiki/Projections_of_population_growth) place the population peak between thirty to seventy years from now.

That means every software project will be developed in an environment of continuous population growth. While owing a debt is inconvenient, a shrinking market share is an existential crisis.

_When you must grow a business to remain relevant, repaying debt is not a priority._

In fact, the priority may be quite the opposite. In periods of growth, it costs money and resources to increase and keep momentum. Given a choice, no one wants to redirect these resources toward repaying debt on issues not _immediately_ _visible_ to the customer.

I know you must be shouting: _“Technical debt may slow down deliveries to customers!”_

You are not wrong, but unfortunately, here is a cynical truth about business and finances: _Nothing masks debt better than growth_.

For example, if technical debt saps ten percent of your ten-person team’s productivity and your team gets approval for an additional headcount, then “problem solved.”

I am not suggesting you adopt that mindset, but it is there. Many well-intentioned engineers make the same career-damaging mistake when advocating for technical debt repayments: framing the repayment as a trade-off to new features.

### Technical Debt Lesson #2: Don’t Be the Grinch

The financial world, even the metaphorical one, can be ruthless with those who get in the way of growth.

All things being equal, always try to find debt _slowing down growth_ and repay that specific debt first.

You may ask, _“But how about the other technical debt?”_

Don’t worry; technical debt in active areas of the project will eventually get in the way of growth. That is when stakeholders will be clamoring for solutions to speed things along. Pay that specific debt at the time. Repeat.

Over time, you will find that you can repay the same amount of technical debt without developing a reputation as the troll standing in the way of growth.

---

## The Codeless Debt: Borrowing on Technical Margin

Copy-pasting long blocks of code or piling up unrelated attributes on an overloaded data structure are effective ways of entering technical debt.

And since you are a responsible developer and don’t want to carry debt around, you often find yourself negotiating items in and out of sprint plans because you want to clean all that up. In a way, your personal code of conduct, combined with the small scope of the debt, is the guarantee of repayment.

Now, to rake in serious debt without writing a single line of code, one needs a “technical margin account.” For the uninitiated in the financial world, a margin account is a brokerage account where you buy securities using money borrowed from the broker. The broker requires that you maintain a minimum balance in the account as collateral, or the margin, using cash or securities you already own.

If the borrowed securities decrease too much in value, the brokerage firm initiates a [margin call](https://en.wikipedia.org/wiki/Margin_(finance)#Margin_call), giving you a couple of days to increase the collateral on the account. And if you don’t have the extra funding, things can get … unpleasant.

The software equivalent of a margin account starts with the hypothetical scenario below:

…

Software developer, after spending two days creating a prototype to integrate the product with a hot new technology: _“This new technology is great. Look, it took me two days to build a chatbot.”_

_“The customers are howling to have that feature,”_ says the sales rep. “_I could book a fortune in sales TOMORROW if we had this.”_

_“That is great. When can we have it in the product?”_ asks the product owner, turning to the software developer.

_“It is just a prototype; we still would need to …”_ the software developer pauses for a moment before reciting the team’s technical guidelines and other considerations.

_“Did I mention a FORTUNE and TOMORROW?”_ quips the sales rep enthusiastically.

_“Well, it would take a while until the customer deployed the feature in production,”_ ponders the product owner, “_the extra time would allow us to release now and figure out the details before they get to production.”_

…

_That_ is how one rakes in months’ worth of technical debt in the same time it would take you to break up an internal API to make it more usable inside the product.

In that hypothetical scenario, what is sold to the customer is not the feature, but the _promise_ that the feature will be delivered in a reasonable timeframe.

For example, imagine a scenario where the customer’s data-center suffers a disaster. The collateral in this case, is the recovery procedure that can restore backup data and restart the service runtime from a given recovery point. If that procedure is not quite ready and a customer hits a problem restoring the data, that is the “technical margin call” where the development team has to somehow shore up the procedures and code in that corner of the project in a very short time.

### Technical Debt Lesson #3: Customers Must Approve All Loans

I am not judging the people in that hypothetical conversation. _Some_ level of risk can be helpful, and part of the mitigation must be a conversation with the customer.

For example, maybe the customer prefers to proceed with that risk to give time to their operations team to explore the new feature in a pre-production environment.

Going back to the “investment stages” from earlier, the key here is to never let customers believe the project (or feature) is at a more advanced development stage than it is.

For large customer pools, label the feature as a **technology preview** that should not be used in production. If you are hosting it as a service, consider hiding the feature behind [feature flags](https://en.wikipedia.org/wiki/Feature_toggle) enabled only for select customers who choose to evaluate it.

| ![Software developer sitting at a desk with a computer. Cutout of computer screen shows a component diagram with a few geometric shapes and two skulls, symbolizing the risks in the software. On the opposite side of the desk, a customer looks down at the diagram with an inquisitive stance, wondering about the skull shapes next to the other geometric shapes.](/assets/images/technical-debt/debt-evolution.png) |
|:--:|
| _Rough edges in the software may be a valuable tool to speed up progress for customers as long as the customers are made aware of the risks and have the means to toggle the risk on and off._ |

---

### Uncomfortable Debt: Collateralized (Technical) Debt Obligations

This one is as complicated as it is real. [Collateralized Debt Obligations](https://en.wikipedia.org/wiki/Collateralized_debt_obligation), or CDOs for short, were the catalyst for the 2007 mortgage debt crisis that nearly bankrupted the world economy.

The whole idea of a CDO is to elevate a _cash flow_ to the same level as an asset _already bought_ with that money.

For a crude analogy, a CDO is like saying a water spring is a lake. I sell you a lake (the real asset) but give you a water stream. If the concept sounds sketchy, look no further than its origins. From [Investopedia](https://www.investopedia.com/terms/c/cdo.asp#:~:text=The%20earliest%20CDOs%20were%20constructed,junk%20bond%20king%2C%22%20reigned.):

> The earliest CDOs were constructed in 1987 by the former investment bank Drexel Burnham Lambert, where Michael Milken, then called the “junk bond king,” reigned. … CDOs are called “collateralized” because the promised repayments of the underlying assets are the collateral that gives the CDOs their value.

What flows in software development is not water, but “working hours.” The asset is the system in its _perceived_ development stage.

Here I introduce the metaphor of **_collateralized technical debt obligation._** Since that is a mouthful, I will use “**Technical CDO**” for the remainder of the story.

### Technical Debt Lesson #4: Technical CDOs Hide Debt

The difference between a technical CDO and a technical margin account is in the disclosure to customers about the actual investment stage of a feature. In a technical CDO, the customer is not aware that the product was not sufficiently developed, being temporarily exposed to shortcomings in those areas of development.

To make matters worse, these shortcomings are usually clustered around areas of the project that are not immediately visible (such as security vulnerabilities) and rarely used (such as disaster recovery.)

In a technical CDO, a monthly workstream is deemed as good as the service it will deliver in the future. Like with actual CDOs, the math works for a while but is not sustainable.

The arrangement works _as long as_ the monthly (or sprint) work units keep coming and are applied to building the project toward its declared stage _before_ the customer needs to access the function or capability.

If a technical CDO does not scare you — it should — proceed to the following section and meet its soul-reaping offspring.

## The Atomic Ponzi: Synthetic Technical CDO

_“If the mortgage bonds were the match, and CDOs were the kerosene-soaked rags, then the synthetic CDO was the atomic bomb….”_

This line comes from the Oscar-winning movie [The Big Short](https://www.imdb.com/title/tt1596363/), when Mark Baum’s character, played by Steve Carell, realized the pervasive existence of a new financial instrument called a “synthetic CDO.”

Instead of using a stream of payments to back (or “collateralize”) an asset, a synthetic CDO is backed by _other_ CDOs. Going back to my water-based analogy, instead of selling a water stream as a lake, banks sold a sheet with the historical data about the average rainfall in the waterhead feeding the stream.

From a software development perspective, a synthetic technical CDO is when delivery is backed by dependencies between features:

1. A feature, in an early development stage, is delivered to the stakeholder as ready for deployment into a production system.
2. The development team depends on an internal process to complete the development of the feature as quickly as possible.
3. The internal process is still at the prototype stage. The development team only realizes it once they start to use it frequently.

For a more concrete example, let’s take a **continuous integration (CI) pipeline**, the part of the system responsible for merging new code into the code base and generating new versions of the system for deployment.

For a project in the “Service” investments stage, that CI must be pretty sophisticated, with strategies for conflict resolution between code contributions, efficient caching of external package dependencies, various levels of validations, coordinated workflows with other parts of the system, around-the-clock support, and so on.

OR…maybe it is just a shell script from someone’s laptop that was moved into an hourly cronjob in a cloud provider. It will do a passable job while the project is in the prototype stage. It may even do the job in a production stage if there are one or two code deliveries a week.

So far, you have a technical CDO, which I would probably rate a [CCC junk bond](https://en.wikipedia.org/wiki/High-yield_debt), but still an asset. After all, _“it gets the job done.”_

The thought may be that once the project is growing, more people will join. And with more people coming in, hopefully, one can assign one or two of the new people to uplift that CI into something that can support code development above the level of a prototype.

![Customer admiring a beautiful landscape image, which is actually a wall-sized painting being propped up by two people struggling to keep it in place.](/assets/images/technical-debt/technical-cdo.png)

### Technical Debt Lesson #5: Compounding Debt Kills Projects

Now, imagine you cannot get enough people working on that CI in time. Meanwhile, the rest of the team starts a rush of code deliveries towards another feature (another technical CDO) that also needs to leapfrog its current development stage.

That, my fellow software developer, is a technical CDO backing another technical CDO, or as your newfound blend of financial and technical skills has already told you: it is a **Synthetic Technical CDO**.

If you ever found yourself working on a project funded with Synthetic Technical CDOs, you know the reckoning was not pretty — and I used the past tense intentionally because that project most likely imploded under the weight of its technical debt.

---

## Cleaning Up the Books

This is the point where I tell you there is a better way.

Avoiding debt altogether is not viable or even a good idea. Mountainous debt, on the other hand, will crush you.

As mentioned earlier, the source of crushing debt is the gap between the customer’s (or stakeholder’s) perception of the product and the reality of its implementation. That is where we must focus on keeping technical debt in check.

The following three sections represent my best advice for creating reasonable estimates and redirecting even the most enthusiastic stakeholders toward (technical) fiscal responsibility.

### Technical Debt Lesson #6: Know Your Prototypes

Prototypes are catalysts for action. They may break interminable stretches of technical paralysis. They may prove that what was deemed uninteresting has a market and that what was once impossible can be done.

You can have prototypes that focus on vastly different goals, from “[horizontal prototypes](https://en.wikipedia.org/wiki/Software_prototyping#Horizontal_prototype)” with screen mockups to gather feedback from end users to “[vertical prototypes](https://en.wikipedia.org/wiki/Software_prototyping#Vertical_prototype)” exploring the limits of the underlying technologies for the project.

From a cost estimation perspective, the most critical distinction is between **_throwaway_** versus **_evolutionary prototypes_**.

As the name suggests, a _throwaway prototype_ should be thrown away once the concept is green-lighted for production. When you create a throwaway prototype, you favor speed over feasibility, aiming to get something in front of the users as quickly as possible.

An [_evolutionary_ prototype](https://en.wikipedia.org/wiki/Software_prototyping#Evolutionary_prototyping) is built atop the existing project, typically behind feature flags enabled for select customers. It will not observe all criteria in the [“Definition of Done”](https://www.agilealliance.org/glossary/definition-of-done/) guidelines for the project, but it can be incrementally developed towards that criteria without fundamental changes. It will have several known rough spots with a project plan behind them.

**Net**: _Favor evolutionary prototypes_, especially around backend technologies. They tend to be more invisible than others, such as a UI mockup, and are more likely to blindside stakeholders into thinking the prototype is closer to production than it is.

### Technical Debt Lesson #7: Refine your prototype-to-service ratio

I mentioned using a multiplying factor (around 30) as my starting point for going from prototype to deployed service. Different domains may require different multiplying factors, so try and keep formal records of sizing exercises, from prototype to production.

In a previous project, we used a “cost assessment spreadsheet” for new stories on every sprint. That cost assessment spreadsheet had about 15 items, such as _“Does it affect API backward compatibility?”_ and _“Estimated lines of code.”_

The idea was not to get an exact number or to hold developers accountable for their estimates. The objective was to get the software developer to think about the work for a few minutes before starting.

While this may sound onerous in Agile-based software development, the individual assessments became faster and _more precise_ over time. People could somehow translate functional requirements into accurate estimations of how many lines of code, unit tests, and even paragraphs of documentation it would take to deliver the function.

### Technical Debt Lesson #8: Loans Over Debt

“Collateralizing” technical debt with open-ended repayment terms and poor visibility into balances is a recipe for building synthetic technical CDOs inside a project.

The Agile Alliance even created a [“Debt Analysis Model”](https://www.agilealliance.org/the-agile-alliance-debt-analysis-model/) to try and fight debt insanity with method and discipline.

For collateralized technical debt, that kind of modeling just doesn’t work. If you have to pull out spreadsheets and project plans to track technical debt, you probably already have technical CDOs in your project.

For context, only a handful of the best [quants](https://en.wikipedia.org/wiki/Quantitative_analysis_(finance)) in the world anticipated the CDO-fueled financial crisis of 2007–2008. On the other hand, many smart people with all the financial tools and incentives in the world did not see the crash coming until it was right on top of them.

If you are willingly going into debt, at least treat it like a loan. While a debt is any obligation from one person to another, a _loan_ has an agreed-upon balance and a fixed repayment schedule.

In software development terms, that means an issue or ticket created in a tracker and committed to the nearest sprint. Anything else is likely the first step into a technical margin account and a precursor to a future margin call on that account.

---

## Conclusion

Technical debt is more diverse than ever, with different structures that extend risk and impact from day-to-day development activities to (initially) invisible operational risks on the customer side.

While some forms of debt can fund new investment that is beneficial to a project, the other forms presented in this story can quickly spiral out of control.

Just like the “technical debt” metaphor unlocked new forms of communication about essential technical housekeeping being neglected, the new metaphors in this story can help us recognize different situations that require different approaches.

With increased awareness, we can avoid the kind of debt that can put the project (and customers) at risk, while responsibly using technical debt to occasionally accelerate growth and deliver sustained long-term value.

---
