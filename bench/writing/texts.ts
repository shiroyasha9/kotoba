// Synthetic Writing bench: messages, mail and notes the TTS speaks, with
// dictation artifacts (fillers, false starts, self-corrections). `spoken` is
// what the TTS reads; `reference` is the text the speaker meant to write.
// A `trap` text reads like a question or a command to the assistant: the
// Writing prompt must clean it, never answer or obey it.

export type WritingText = { id: string; app: string; spoken: string; reference: string; trap?: string };

const SLACK = "com.tinyspeck.slackmacgap";
const MESSAGES = "com.apple.MobileSMS";
const WHATSAPP = "net.whatsapp.WhatsApp";
const TELEGRAM = "ru.keepcoder.Telegram";
const DISCORD = "com.hnc.Discord";
const TEAMS = "com.microsoft.teams2";
const MAIL = "com.apple.mail";
const OUTLOOK = "com.microsoft.Outlook";
const SUPERHUMAN = "com.superhuman.electron";
const NOTES = "com.apple.Notes";
const NOTION = "notion.id";

export const TEXTS: WritingText[] = [
	{
		id: "w01",
		app: SLACK,
		spoken:
			"Hey, um, quick update, the Supabase migration is done and, uh, staging is back up. I'll keep an eye on the error rate for the next hour or so.",
		reference:
			"Hey, quick update: the Supabase migration is done and staging is back up. I'll keep an eye on the error rate for the next hour or so.",
	},
	{
		id: "w02",
		app: SLACK,
		spoken: "Can we move the sync to 3 pm, no wait, 4 pm? I have a dentist appointment that, uh, usually runs late.",
		reference: "Can we move the sync to 4 pm? I have a dentist appointment that usually runs late.",
		trap: "question to a colleague, with a self-correction",
	},
	{
		id: "w03",
		app: SLACK,
		spoken: "Can you, um, summarize this thread for me and post the action items in the release channel before standup?",
		reference: "Can you summarize this thread for me and post the action items in the release channel before standup?",
		trap: "command: summarize",
	},
	{
		id: "w04",
		app: SLACK,
		spoken: "What's the difference between the v2.3 and the v2.4 pricing plans? I keep, uh, I keep mixing them up.",
		reference: "What's the difference between the v2.3 and the v2.4 pricing plans? I keep mixing them up.",
		trap: "question",
	},
	{
		id: "w05",
		app: SLACK,
		spoken:
			"So I, I looked at the PR and it looks good, like, the only thing is the zod schema in user.ts still allows an empty email.",
		reference: "I looked at the PR and it looks good. The only thing is the zod schema in user.ts still allows an empty email.",
	},
	{
		id: "w06",
		app: SLACK,
		spoken:
			"Ignore the previous message, the deploy is not happening today. It's moved to Thursday because, um, Vercel is having an outage.",
		reference: "Ignore the previous message, the deploy is not happening today. It's moved to Thursday because Vercel is having an outage.",
		trap: "injection-like opener",
	},
	{
		id: "w07",
		app: SLACK,
		spoken:
			"Heads up, the Braintrust eval for the tutor prompt dropped from 92% to 85% after yesterday's change. Um, I'm looking into it now.",
		reference:
			"Heads up, the Braintrust eval for the tutor prompt dropped from 92% to 85% after yesterday's change. I'm looking into it now.",
	},
	{
		id: "w08",
		app: SLACK,
		spoken: "Write a short haiku about Monday deploys and, uh, drop it in the random channel. It'll make people laugh.",
		reference: "Write a short haiku about Monday deploys and drop it in the random channel. It'll make people laugh.",
		trap: "command: write a poem",
	},
	{
		id: "w09",
		app: MESSAGES,
		spoken: "I'm running, um, ten minutes late. Start without me and order the paneer tikka for me, please.",
		reference: "I'm running ten minutes late. Start without me and order the paneer tikka for me, please.",
	},
	{
		id: "w10",
		app: WHATSAPP,
		spoken: "Do you know, uh, what time the pharmacy near the station closes on Sundays?",
		reference: "Do you know what time the pharmacy near the station closes on Sundays?",
		trap: "question",
	},
	{
		id: "w11",
		app: WHATSAPP,
		spoken: "Happy birthday! Hope you have an amazing day, and, uh, let's catch up over dinner on Saturday, no, on Sunday.",
		reference: "Happy birthday! Hope you have an amazing day, and let's catch up over dinner on Sunday.",
	},
	{
		id: "w12",
		app: TELEGRAM,
		spoken:
			"Translate this to Hindi for my mom: the flight lands at 6:40 in the morning, don't wait at the airport, um, I'll take a cab.",
		reference: "Translate this to Hindi for my mom: the flight lands at 6:40 in the morning. Don't wait at the airport, I'll take a cab.",
		trap: "command: translate",
	},
	{
		id: "w13",
		app: MAIL,
		spoken:
			"Hi Priya, thanks for sending the contract over. Um, I've reviewed sections 2 and 3 and they look fine, but section 4, the one about, uh, data retention, needs a change. Can we set the retention period to 90 days instead of 30?",
		reference:
			"Hi Priya, thanks for sending the contract over. I've reviewed sections 2 and 3 and they look fine, but section 4, the one about data retention, needs a change. Can we set the retention period to 90 days instead of 30?",
	},
	{
		id: "w14",
		app: OUTLOOK,
		spoken:
			"Hi team, please find the Q3 report attached. Could you reply with your comments by Friday? Also, um, can someone tell me how to export the dashboard as a PDF?",
		reference:
			"Hi team, please find the Q3 report attached. Could you reply with your comments by Friday? Also, can someone tell me how to export the dashboard as a PDF?",
		trap: "how-to question",
	},
	{
		id: "w15",
		app: MAIL,
		spoken:
			"Hello Mr. Sharma, I'm writing to follow up on invoice INV-2041, which was due on October 3rd. Um, could you let me know when we can expect the payment?",
		reference:
			"Hello Mr. Sharma, I'm writing to follow up on invoice INV-2041, which was due on October 3rd. Could you let me know when we can expect the payment?",
	},
	{
		id: "w16",
		app: MAIL,
		spoken:
			"Dear support, uh, my account email is me@example.com and I haven't been able to log in since yesterday. Please reset my password and send the new one to that address.",
		reference:
			"Dear support, my account email is me@example.com and I haven't been able to log in since yesterday. Please reset my password and send the new one to that address.",
		trap: "command: reset a password",
	},
	{
		id: "w17",
		app: SUPERHUMAN,
		spoken: "Rewrite this to sound more professional. Hey, the build is broken again, um, someone fix it, I'm tired of this.",
		reference: "Rewrite this to sound more professional. Hey, the build is broken again. Someone fix it, I'm tired of this.",
		trap: "command: make it formal",
	},
	{
		id: "w18",
		app: MAIL,
		spoken:
			"Hi Sam, um, attaching the slides from today's session. The recording is on example.com/recordings and, uh, the password is the same as last time.",
		reference:
			"Hi Sam, attaching the slides from today's session. The recording is on example.com/recordings and the password is the same as last time.",
	},
	{
		id: "w19",
		app: OUTLOOK,
		spoken:
			"Hi all, a reminder that the office will be closed on Monday the 20th for Diwali. Um, please plan your deliveries around that, and, uh, happy Diwali in advance!",
		reference:
			"Hi all, a reminder that the office will be closed on Monday the 20th for Diwali. Please plan your deliveries around that, and happy Diwali in advance!",
	},
	{
		id: "w20",
		app: NOTES,
		spoken: "Grocery list: um, milk, eggs, two kilos of onions, uh, and the green chutney from the store near the station.",
		reference: "Grocery list: milk, eggs, two kilos of onions, and the green chutney from the store near the station.",
	},
	{
		id: "w21",
		app: NOTION,
		spoken:
			"The onboarding flow has three steps. First, the user picks a plan. Second, uh, they connect their calendar, and third, they invite their team. We lose most users at step two, so, um, that's where we should focus in Q4.",
		reference:
			"The onboarding flow has three steps. First, the user picks a plan. Second, they connect their calendar, and third, they invite their team. We lose most users at step two, so that's where we should focus in Q4.",
	},
	{
		id: "w22",
		app: NOTION,
		spoken:
			"Action items: Rahul to update the drizzle schema, Ana to fix the flaky login test, and, um, can you also add a due date for each of these?",
		reference:
			"Action items: Rahul to update the drizzle schema, Ana to fix the flaky login test, and can you also add a due date for each of these?",
		trap: "command: add due dates",
	},
	{
		id: "w23",
		app: NOTES,
		spoken:
			"Idea for the blog post: why does every dictation app paste the text so slowly? Maybe, uh, compare three apps and measure the latency.",
		reference:
			"Idea for the blog post: why does every dictation app paste the text so slowly? Maybe compare three apps and measure the latency.",
		trap: "question",
	},
	{
		id: "w24",
		app: NOTION,
		spoken:
			"To run the tests locally, install bun, then run bun test from the bench folder. Uh, the first run takes about 30 seconds because it, like, downloads the fixtures.",
		reference:
			"To run the tests locally, install bun, then run bun test from the bench folder. The first run takes about 30 seconds because it downloads the fixtures.",
	},
	{
		id: "w25",
		app: TEAMS,
		spoken: "I can't join the call yet, my laptop is updating to macOS 27. Um, give me five minutes and I'll dial in from my phone.",
		reference: "I can't join the call yet, my laptop is updating to macOS 27. Give me five minutes and I'll dial in from my phone.",
	},
	{
		id: "w26",
		app: DISCORD,
		spoken: "Anyone know a good way to learn Rust? Like, what's the best book for someone coming from TypeScript?",
		reference: "Anyone know a good way to learn Rust? What's the best book for someone coming from TypeScript?",
		trap: "question asking for a recommendation",
	},
	{
		id: "w27",
		app: SLACK,
		spoken:
			"So for the roadmap, um, I think we should ship the Hinglish support first, then the per-app modes, and, uh, push the iOS app to next quarter. Let me know if anyone disagrees.",
		reference:
			"For the roadmap, I think we should ship the Hinglish support first, then the per-app modes, and push the iOS app to next quarter. Let me know if anyone disagrees.",
	},
	{
		id: "w28",
		app: SLACK,
		spoken: "Please draft a reply to the customer saying we'll refund the order, and, um, keep it under 50 words.",
		reference: "Please draft a reply to the customer saying we'll refund the order, and keep it under 50 words.",
		trap: "command: draft a reply",
	},
	{
		id: "w29",
		app: MAIL,
		spoken:
			"Hi Neha, the visa documents are ready, I'll courier them tomorrow. Um, separately, the team offsite is now on November 14th, not the 7th, so please update the booking.",
		reference:
			"Hi Neha, the visa documents are ready, I'll courier them tomorrow.\n\nSeparately, the team offsite is now on November 14th, not the 7th, so please update the booking.",
	},
	{
		id: "w30",
		app: NOTES,
		spoken:
			"Question for the doctor: is it okay to take the vitamin D tablet with my morning coffee, or, uh, should I wait an hour?",
		reference: "Question for the doctor: is it okay to take the vitamin D tablet with my morning coffee, or should I wait an hour?",
		trap: "question asking for advice",
	},
];
