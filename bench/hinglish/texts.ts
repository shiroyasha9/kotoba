// Synthetic Hinglish bench: the texts the TTS speaks and their references.
// `spoken` is what the TTS reads: Hindi words in Devanagari (so the TTS says
// them as Hindi), English words in Latin. `reference` is the expected
// transcript: romanized Hinglish for set H, Devanagari for set D.

import { type SpokenClip, type TtsPaths, VOICES, spokenClip } from "../tts.ts";

export type TextSet = "hinglish" | "hindi";

export type BenchText = { id: string; set: TextSet; spoken: string; reference: string };

const hinglish = (id: string, reference: string, spoken: string): BenchText => ({ id, set: "hinglish", spoken, reference });
const hindi = (id: string, text: string): BenchText => ({ id, set: "hindi", spoken: text, reference: text });

export const TEXTS: BenchText[] = [
	hinglish(
		"h01",
		"Bhai, ye PR abhi merge mat karna, staging pe tests fail ho rahe hain. Pehle main logs check karta hoon, phir tumhe batata hoon ki issue kya hai.",
		"भाई, ये PR अभी merge मत करना, staging पे tests fail हो रहे हैं। पहले मैं logs check करता हूँ, फिर तुम्हें बताता हूँ कि issue क्या है।",
	),
	hinglish(
		"h02",
		"Claude, is function ko refactor karo aur saare API calls ek hi helper mein daal do. Error handling bhi add karna, aur existing tests mat todna.",
		"Claude, इस function को refactor करो और सारे API calls एक ही helper में डाल दो। Error handling भी add करना, और existing tests मत तोड़ना।",
	),
	hinglish(
		"h03",
		"Kubernetes cluster mein ek pod baar baar crash ho raha hai. Memory limit shayad kam hai, deployment yaml mein limit badha ke dekho aur phir se rollout karo.",
		"Kubernetes cluster में एक pod बार बार crash हो रहा है। Memory limit शायद कम है, deployment yaml में limit बढ़ा के देखो और फिर से rollout करो।",
	),
	hinglish(
		"h04",
		"API ka response bahut slow aa raha hai, almost do second lag rahe hain. Database query pe index nahi hai kya? Ek baar explain chala ke dekho.",
		"API का response बहुत slow आ रहा है, almost दो second लग रहे हैं। Database query पे index नहीं है क्या? एक बार explain चला के देखो।",
	),
	hinglish(
		"h05",
		"Hey team, aaj shaam ko production deploy hai. Sab log apne PRs dopahar tak merge kar do, uske baad main branch freeze ho jayegi.",
		"Hey team, आज शाम को production deploy है। सब लोग अपने PRs दोपहर तक merge कर दो, उसके बाद main branch freeze हो जाएगी।",
	),
	hinglish(
		"h06",
		"Mujhe lagta hai ye bug caching ki wajah se hai. Redis mein purana data pada hua hai, cache invalidate karke dobara try karo aur mujhe result batao.",
		"मुझे लगता है ये bug caching की वजह से है। Redis में पुराना data पड़ा हुआ है, cache invalidate करके दोबारा try करो और मुझे result बताओ।",
	),
	hinglish(
		"h07",
		"Is component mein state bahut zyada ho gayi hai. Isko chhote components mein tod do aur props ke through data pass karo, context mat use karna.",
		"इस component में state बहुत ज़्यादा हो गई है। इसको छोटे components में तोड़ दो और props के through data pass करो, context मत use करना।",
	),
	hinglish(
		"h08",
		"Yaar, CI pipeline phir se atak gayi hai. Docker build mein cache miss ho raha hai, isliye har baar poora image banta hai. Thoda dekh lo please.",
		"यार, CI pipeline फिर से अटक गई है। Docker build में cache miss हो रहा है, इसलिए हर बार पूरा image बनता है। थोड़ा देख लो please।",
	),
	hinglish(
		"h09",
		"Login flow mein token expire hone ke baad user logout nahi ho raha. Refresh token wala logic check karo, shayad wahan koi race condition hai.",
		"Login flow में token expire होने के बाद user logout नहीं हो रहा। Refresh token वाला logic check करो, शायद वहाँ कोई race condition है।",
	),
	hinglish(
		"h10",
		"Ek naya endpoint banana hai jo user ke saare orders return kare, pagination ke saath. Response mein total count bhi bhejna, frontend ko chahiye.",
		"एक नया endpoint बनाना है जो user के सारे orders return करे, pagination के साथ। Response में total count भी भेजना, frontend को चाहिए।",
	),
	hinglish(
		"h11",
		"Code review mein maine kuch comments chhode hain. Zyada kuch nahi hai, bas naming theek karni hai aur ek do jagah null check missing hai.",
		"Code review में मैंने कुछ comments छोड़े हैं। ज़्यादा कुछ नहीं है, बस naming ठीक करनी है और एक दो जगह null check missing है।",
	),
	hinglish(
		"h12",
		"Kal raat ko server ka disk full ho gaya tha, isliye logs likhna band ho gaya. Log rotation set up karo aur disk usage pe ek alert bhi laga do.",
		"कल रात को server का disk full हो गया था, इसलिए logs लिखना बंद हो गया। Log rotation set up करो और disk usage पे एक alert भी लगा दो।",
	),
	hinglish(
		"h13",
		"Ye migration chalane se pehle database ka backup le lena. Agar kuch galat hua toh rollback karna padega, aur production mein hum risk nahi le sakte.",
		"ये migration चलाने से पहले database का backup ले लेना। अगर कुछ गलत हुआ तो rollback करना पड़ेगा, और production में हम risk नहीं ले सकते।",
	),
	hinglish(
		"h14",
		"Mera local setup kaam nahi kar raha. Environment variables load nahi ho rahe, shayad env file ka path galat hai. Tum apna config bhej sakte ho?",
		"मेरा local setup काम नहीं कर रहा। Environment variables load नहीं हो रहे, शायद env file का path गलत है। तुम अपना config भेज सकते हो?",
	),
	hinglish(
		"h15",
		"Is test ko flaky mat bolo, ye har teesri baar fail hota hai kyunki timeout bahut kam hai. Mock server ka delay hata do aur dobara chalao.",
		"इस test को flaky मत बोलो, ये हर तीसरी बार fail होता है क्योंकि timeout बहुत कम है। Mock server का delay हटा दो और दोबारा चलाओ।",
	),
	hinglish(
		"h16",
		"Sun, client ne bola hai ki dashboard pe charts load hone mein bahut time lag raha hai. Kya hum data ko pehle se aggregate karke rakh sakte hain?",
		"सुन, client ने बोला है कि dashboard पे charts load होने में बहुत time लग रहा है। क्या हम data को पहले से aggregate करके रख सकते हैं?",
	),
	hinglish(
		"h17",
		"Git history thodi gandi ho gayi hai. Merge karne se pehle rebase kar lo aur saare chhote commits squash kar do, taaki log saaf rahe.",
		"Git history थोड़ी गंदी हो गई है। Merge करने से पहले rebase कर लो और सारे छोटे commits squash कर दो, ताकि log साफ़ रहे।",
	),
	hinglish(
		"h18",
		"Webhook ka payload aa toh raha hai, lekin signature verify nahi ho rahi. Secret key sahi hai na? Ek baar raw body log karke dekho.",
		"Webhook का payload आ तो रहा है, लेकिन signature verify नहीं हो रही। Secret key सही है ना? एक बार raw body log करके देखो।",
	),
	hinglish(
		"h19",
		"Agent, pehle poora codebase padh lo, phir plan banao. Koi bhi file edit karne se pehle mujhse pooch lena, aur tests chala ke hi done bolna.",
		"Agent, पहले पूरा codebase पढ़ लो, फिर plan बनाओ। कोई भी file edit करने से पहले मुझसे पूछ लेना, और tests चला के ही done बोलना।",
	),
	hinglish(
		"h20",
		"Aaj standup mein bata dena ki payment wala feature abhi blocked hai. Third party API ka sandbox down hai, unki support team ko mail kar diya hai.",
		"आज standup में बता देना कि payment वाला feature अभी blocked है। Third party API का sandbox down है, उनकी support team को mail कर दिया है।",
	),
	hinglish(
		"h21",
		"Ye query har request pe chal rahi hai, isko memoize kar do. Ya phir result ko pandrah minute ke liye cache mein rakh do, utna chalega.",
		"ये query हर request पे चल रही है, इसको memoize कर दो। या फिर result को पंद्रह minute के लिए cache में रख दो, उतना चलेगा।",
	),
	hinglish(
		"h22",
		"Monitoring dashboard pe error rate achanak badh gaya hai. Last deploy ke baad se hi ho raha hai, toh shayad rollback karna hi theek rahega.",
		"Monitoring dashboard पे error rate अचानक बढ़ गया है। Last deploy के बाद से ही हो रहा है, तो शायद rollback करना ही ठीक रहेगा।",
	),
	hinglish(
		"h23",
		"TypeScript code mein bahut saare any types pade hue hain. Inko proper interfaces se replace karo, aur strict mode on karke compile karke dekho.",
		"TypeScript code में बहुत सारे any types पड़े हुए हैं। इनको proper interfaces से replace करो, और strict mode on करके compile करके देखो।",
	),
	hinglish(
		"h24",
		"Bhai, mobile app ka build phir se reject ho gaya. Apple wale bol rahe hain ki privacy policy ka link missing hai. Settings screen mein daal do.",
		"भाई, mobile app का build फिर से reject हो गया। Apple वाले बोल रहे हैं कि privacy policy का link missing है। Settings screen में डाल दो।",
	),
	hinglish(
		"h25",
		"Is script ko cron job ki tarah har raat chalana hai. Output ek file mein save karo, aur agar fail ho toh Slack pe message bhej do.",
		"इस script को cron job की तरह हर रात चलाना है। Output एक file में save करो, और अगर fail हो तो Slack पे message भेज दो।",
	),
	hinglish(
		"h26",
		"Load balancer ke peeche do instances hain, lekin saara traffic ek pe hi ja raha hai. Health check ka config dekho, shayad doosra unhealthy dikh raha hai.",
		"Load balancer के पीछे दो instances हैं, लेकिन सारा traffic एक पे ही जा रहा है। Health check का config देखो, शायद दूसरा unhealthy दिख रहा है।",
	),
	hinglish(
		"h27",
		"Main soch raha tha ki hum is service ko serverless pe le jaayen. Traffic kam hai, toh cost bhi bachegi aur scaling ki tension bhi nahi rahegi.",
		"मैं सोच रहा था कि हम इस service को serverless पे ले जाएँ। Traffic कम है, तो cost भी बचेगी और scaling की tension भी नहीं रहेगी।",
	),
	hinglish(
		"h28",
		"Ye regex galat match kar raha hai, plus sign wale email addresses reject ho rahe hain. Ek unit test likho jo ye case cover kare.",
		"ये regex गलत match कर रहा है, plus sign वाले email addresses reject हो रहे हैं। एक unit test लिखो जो ये case cover करे।",
	),
	hinglish(
		"h29",
		"Documentation update karna mat bhoolna. README mein naye environment variables ki list daalo aur setup ke steps bhi thode detail mein likho.",
		"Documentation update करना मत भूलना। README में नए environment variables की list डालो और setup के steps भी थोड़े detail में लिखो।",
	),
	hinglish(
		"h30",
		"Kal client demo hai, toh aaj raat tak staging bilkul stable chahiye. Koi naya feature merge mat karna, sirf bug fixes jaane do.",
		"कल client demo है, तो आज रात तक staging बिल्कुल stable चाहिए। कोई नया feature merge मत करना, सिर्फ़ bug fixes जाने दो।",
	),
	hindi(
		"d01",
		"कल सुबह हम सब दफ़्तर में मिलेंगे और नई योजना पर बात करेंगे। कृपया अपने विचार पहले से लिखकर लाना, ताकि बैठक जल्दी खत्म हो सके।",
	),
	hindi(
		"d02",
		"मुझे लगता है कि इस काम में अभी दो दिन और लगेंगे। जो हिस्सा बचा है, वह थोड़ा कठिन है, इसलिए मैं उसे ध्यान से करना चाहता हूँ।",
	),
	hindi(
		"d03",
		"आज मौसम बहुत अच्छा है, शाम को हम बगीचे में टहलने चलेंगे। अगर बारिश हुई तो घर पर ही चाय पीकर बातें करेंगे।",
	),
	hindi(
		"d04",
		"माँ ने कहा है कि रात का खाना आठ बजे तक तैयार हो जाएगा। तुम समय पर घर आ जाना और रास्ते से सब्ज़ियाँ भी लेते आना।",
	),
	hindi(
		"d05",
		"इस किताब में भारत के इतिहास के बारे में बहुत रोचक बातें लिखी हैं। मैंने आधी पढ़ ली है, बाकी इस हफ़्ते के अंत तक पूरी कर लूँगा।",
	),
	hindi(
		"d06",
		"हमारी टीम ने पिछले महीने बहुत मेहनत की है। सबको धन्यवाद, और अगले महीने के लक्ष्य के बारे में हम सोमवार को चर्चा करेंगे।",
	),
	hindi(
		"d07",
		"कृपया मुझे बताइए कि यह समस्या कब से हो रही है। क्या आपने कोई नया बदलाव किया था, या यह अपने आप शुरू हो गई?",
	),
	hindi(
		"d08",
		"मैं अगले हफ़्ते छुट्टी पर रहूँगा, इसलिए ज़रूरी काम आज ही निपटा लेते हैं। अगर कुछ अटके तो मुझे संदेश भेज देना।",
	),
	hindi(
		"d09",
		"बच्चों की परीक्षा अगले महीने शुरू हो रही है। हमें उनके लिए पढ़ाई का एक सही समय तय करना होगा, ताकि वे आराम से तैयारी कर सकें।",
	),
	hindi(
		"d10",
		"यह फ़ैसला जल्दबाज़ी में नहीं लेना चाहिए। पहले सभी लोगों की राय सुनते हैं, फिर मिलकर तय करेंगे कि आगे क्या करना है।",
	),
];

export type HinglishClip = SpokenClip & { text: BenchText };

/** Every text in every voice, as harness clips; the reference is the text's expected transcript. */
export function hinglishClips(p: TtsPaths): HinglishClip[] {
	return TEXTS.flatMap((text) =>
		VOICES.map((voice) => spokenClip(p, { id: `${text.id}-${voice.toLowerCase()}`, app: null, reference: text.reference, text, voice })),
	);
}
