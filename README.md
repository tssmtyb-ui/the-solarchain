Spekulant: Project Design Document & Contributor Guide

Welcome to spekulant! We are building the ultimate eco-capitalist sandbox. Spekulant is an open-source 2.5D city builder that trades tedious traffic management for high-stakes macroeconomic puzzles. If you love the intricate supply chains of Anno and the progressive economics of Henry George, you are in the right place.
Whether you are a developer, an artist, an economic theorist, or a player who loves supply chains, we want your help to make this sandbox a reality.
1. The Core Pillars
1. The Aesthetic: 2.5D Eco-Capitalism & Vibrant Tech
The game utilizes a 2.5D isometric perspective, blending classic city-builder readability with modern, optimistic visuals. Players build a world of gleaming white eco-structures, glass bio-domes, and lush vertical gardens integrated directly into nature.
2. The Logistics Puzzle: High-Throughput Networks
We have completely banned traditional road traffic. Instead, the puzzle is about spatial layout and material bandwidth.
Dragging Lines: You physically draw networks across the map, laying down hyperloop freight rails, glowing chemical pipelines, and magnetic mag-lev tracks.
The Bottleneck: Infrastructure has strict capacity limits.
3. The Economic Engine: Flat LVT & Automatic Evolution
The entire financial simulation runs on a gamified Land Value Tax (LVT) that creates an organic, living city.
The Flat Rate: You set one universal tax rate for raw land across the entire map. To change how much tax a district pays, you manipulate the environment.
Environmental Magnets: Building transit hubs and botanical gardens spikes land value. Laying down ugly cargo rails or sludge lines tanks it.
Dynamic Growth: When you boost land value, the simulation automatically responds. The AI will bulldoze a small house and build a massive, high-density skyscraper so they can pack in more tenants to split the expensive tax bill. (Note: We use a strict construction cooldown/buffer to prevent the AI from flickering between building states if land value hovers on a threshold.) You watch the city vertically morph based entirely on how you alter the land value.
4. The Enemy: Corporate Land Speculators To keep you on your toes, AI speculators act as mini-bosses. The map is generally free for you to build on, but the AI will scan for high-value areas and buy up prime real estate, leaving it as an empty, ugly "Dirt Lot". You are blocked from building on their land. You have two ways to reclaim it:
The Gentrification Trap (The Intended Route): Build environmental magnets (parks, transit hubs) around their lot. The land value explodes, and their LVT tax bill skyrockets until they go bankrupt.
Anti-Spam Math: Environmental magnets have diminishing returns. Spamming the exact same park yields zero additional Land Value; players must build a diverse, genuinely high-value district to max out the LVT.
The Civic Consequence: Parks are public goods. They have a 0% refund upon demolition. Furthermore, bulldozing a park outrages the community, instantly triggering a 3-minute Worker Strike at the nearest factory (utilizing the logic from Section 2.4).
The Hostile Buyout (The Emergency Exit): If you are rich and impatient, you can simply click on the Dirt Lot and pay a massive premium (e.g., $500) to buy out the speculator instantly, returning the tile to your control.

2. Core Gameplay & Event Logic (If/Then Rules)
We keep our game mechanics mathematically simple but emergent. Rather than running deep, processor-heavy calculations, we use modular, easily adjustable "if/then" rules:
1. The Pollution Crash & Capital Flight (Miljösmällen)
Instead of calculating complex environmental degradation percentages, we use a simple, visual radius system (similar to fire stations or churches in Anno).
IF the player builds a heavy factory (e.g., a steel smelter), THEN an invisible red circle with a radius of 5 tiles is generated around it.
IF a residential tile lies fully or partially within this red circle, THEN its base Land Value suffers a catastrophic penalty (e.g., -80%). Since the player's income is purely derived from Land Value, their tax revenue from this district organically plummets.
IF a tile's Land Value drops below a structure's minimum sustainment threshold, THEN the AI automatically downgrades the building (e.g., skyscrapers decay into low-density slums or become abandoned).
Why it's fun: It forces players to push heavy industry far away, creating a logistics puzzle of long-distance transport routes. More importantly, there are no arbitrary UI popups or fines. If a player pollutes a neighborhood, they are forced to watch their shimmering eco-utopia physically rot into low-density slums while their economy organically collapses.
2. The Land Hoarding Tax (Spekulationsspärren) Georgism opposes buying up land simply to hold onto it without adding value. Since players build directly on free grass (no manual claiming), this rule strictly targets the AI Speculators.
IF the AI claims a tile and leaves it as a Dirt Lot, THEN they must pay the standard LVT for that tile every tick.
IF the AI holds the tile for more than 5 minutes without developing it, THEN a penalty multiplier is applied, making them bleed cash even faster.
Why it's fun: It ensures the AI can't hold land hostage forever without financial consequence. It turns the AI into a ticking time bomb that the player can actively defeat via the Gentrification Trap.

3. The Citizen's Dividend Policy (Medborgarutdelningen) In a true Georgist economy, land tax revenues are returned directly to the people as a basic income. Instead of disruptive popups and cash-dump exploits, the game features a permanent economic policy slider in the UI.
The Policy Slider: The player sets a continuous dividend percentage (from 0% to 100%) applied directly to incoming LVT revenue.
Linear Scaling: The chosen dividend rate smoothly scales a global factory production multiplier (e.g., higher payouts grant a steady productivity boost, while 0% payout removes the bonus or introduces a minor efficiency penalty).
Why it's fun: It removes annoying popups and game-breaking exploits, replacing them with continuous, smooth strategic control over balancing capital reinvestment versus community dividends.

4. The Public Park Ultimatum (Allmänningens krav) An event-driven obstacle to challenge tight, rigid planning.
Once per hour, the game randomly selects a tile currently occupied by player logistics (e.g., pipes, mag-lev rails) situated in a high-value district. A popup triggers: "The citizens demand a public park on this exact tile!"
IF the player accepts, THEN their infrastructure is instantly bulldozed (no refund), the tile becomes a public park (production buildings are blocked here for 15 minutes), and surrounding land value upgrades. The player must now urgently re-route their severed supply line.
IF the player refuses (to protect their planned supply network), THEN the citizens protest, shutting down the nearest factory for 3 minutes.
Why it's fun: It simulates community ownership over land and prevents players from "cheesing" the event by spamming empty tiles. It creates a brutal, emergent logistical puzzle: do you let the workers strike, or do you sever your own perfectly optimized pipeline to appease the public?

3. Radical Scope Cutting (The Developer's Rules)
To ensure this game is fast to develop, easy to ship, and performant for a solo creator or small group of hobbyists, we have established three non-negotiable scope limits:
Bandwidth Logic Over Agent AI: We do not calculate individual citizens, vehicles, or pathfinding algorithms. If a connection line exists between Point A and Point B, resources flow per sek. It is a system of capacity and pipeline limits, not traffic agents.
Minimalist & Scalable Asset Art: Since our team is small, we use a clean, geometric "minimalist" art style. Sleek, white glass domes and vibrant green gardens are highly aesthetic, easy to standardize, and quick to render without needing a massive team of 3D artists.
Cut the "Nice-to-Haves": If a feature doesn't directly interact with LVT, logistics network layout, or our core events, it gets cut. This means no complex diplomacy, no weather systems, and no narrative character sub-plots. We stay laser-focused on the economic supply chain puzzle.
4. The Contribution Playbook
We are a welcoming, open sandbox! If you want to contribute, keep the following guidelines in mind:
Vibe-First Focus: We prioritize fun, emergent economic gameplay over AAA-grade polish. If a mechanic makes the simulation more engaging, we want it—even if it has some indie "jank."
Functional PRs Only: All feature additions or core logic changes must be submitted as working, tested code. Please clone the repository, run the simulation, and ensure your additions do not crash the economic engine before submitting a Pull Request.
Collaborative Spirit: I am happy to pair-program with you for up to 2 hours to help merge your features into the core engine, but please respect the project's time by arriving with a functional, testable prototype.
Open Sandbox Debates: If you believe a core mechanic (even the speculator AI) should be redesigned or replaced to improve the game, we are completely open to discussing and voting on changes with the community.
5. Let's Build an Eco-Utopia: Join the Project
We are just getting started, and there are plenty of hypotheses left to test. Here is how you can get involved today:
Join the Discord: Jump into our discussion channels to debate economic policies, propose new logistics structures, or share your conceptual art.
Explore the GitHub: Check out our open repository, look at the current codebase, and grab a task from our "Good First Issues" list.
Propose a Hypothesis: Have a theory on how to balance LVT against heavy industry? Write up a quick "If/Then" rule and pitch it to the community.
