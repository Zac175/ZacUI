-- QoL_Data - data tables for the quality-of-life module: the gossip
-- auto-skip NPC list and the mute-sound file IDs. Generated straight
-- from the Leatrix Plus 1.15.150 source (npcTable and Leatrix_Plus_Mute),
-- not retyped - 1570 NPC ids, every fileDataID verbatim.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
-- Zacui_QoL is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

local QoL = {}

-- ============================================================
-- GOSSIP AUTO-SKIP NPCS - stable masters, bankers, flight masters,
-- trainers, vendors and battlemasters. Talking to one of these skips
-- the gossip page with no Alt key needed (Shift suppresses).
-- ============================================================
QoL.GOSSIP_NPCS = {
    [27]=true, [10060]=true, [10063]=true, [9984]=true, [11119]=true, [9985]=true, [11104]=true, [10062]=true, [10085]=true, [9978]=true, [10051]=true, [9988]=true, [10054]=true, [9989]=true,
    [9981]=true, [10056]=true, [13616]=true, [14741]=true, [10045]=true, [10052]=true, [10047]=true, [10055]=true, [9986]=true, [15722]=true, [6749]=true, [10061]=true, [15131]=true, [9979]=true,
    [13617]=true, [11105]=true, [10053]=true, [9983]=true, [9982]=true, [10050]=true, [9980]=true, [11117]=true, [10046]=true, [10059]=true, [16094]=true, [10058]=true, [9987]=true, [10048]=true,
    [9977]=true, [10057]=true, [10049]=true, [11069]=true, [9976]=true, [19]=true, [8356]=true, [2456]=true, [4549]=true, [7799]=true, [4209]=true, [4155]=true, [8123]=true, [3318]=true,
    [3309]=true, [2455]=true, [2625]=true, [2457]=true, [3320]=true, [2461]=true, [2460]=true, [4208]=true, [8124]=true, [5099]=true, [8119]=true, [8357]=true, [3496]=true, [2459]=true,
    [4550]=true, [2996]=true, [13917]=true, [2458]=true, [5060]=true, [21]=true, [10583]=true, [352]=true, [8019]=true, [3838]=true, [10897]=true, [3615]=true, [3310]=true, [2299]=true,
    [12578]=true, [4312]=true, [4267]=true, [1571]=true, [1572]=true, [12616]=true, [16227]=true, [2409]=true, [3841]=true, [2432]=true, [2861]=true, [12740]=true, [12636]=true, [4321]=true,
    [11900]=true, [1573]=true, [2859]=true, [11138]=true, [11901]=true, [6706]=true, [6726]=true, [8610]=true, [11899]=true, [1387]=true, [931]=true, [12596]=true, [3305]=true, [8609]=true,
    [2858]=true, [8018]=true, [4407]=true, [15177]=true, [12577]=true, [2995]=true, [523]=true, [4319]=true, [7823]=true, [10378]=true, [2851]=true, [2835]=true, [2226]=true, [4317]=true,
    [7824]=true, [12617]=true, [2941]=true, [4551]=true, [13177]=true, [11139]=true, [6026]=true, [8020]=true, [2389]=true, [4314]=true, [15178]=true, [28]=true, [11073]=true, [11865]=true,
    [2836]=true, [7948]=true, [5482]=true, [11867]=true, [11052]=true, [11097]=true, [8736]=true, [5159]=true, [11072]=true, [4160]=true, [11869]=true, [11870]=true, [7406]=true, [1386]=true,
    [8126]=true, [2327]=true, [3399]=true, [11098]=true, [1346]=true, [5513]=true, [11868]=true, [11557]=true, [2704]=true, [6287]=true, [4165]=true, [4732]=true, [5567]=true, [11866]=true,
    [5174]=true, [2399]=true, [11074]=true, [5518]=true, [7944]=true, [4611]=true, [6707]=true, [3373]=true, [6291]=true, [3412]=true, [3352]=true, [12042]=true, [7088]=true, [7870]=true,
    [4211]=true, [1218]=true, [1292]=true, [4212]=true, [4258]=true, [6306]=true, [4752]=true, [1317]=true, [7311]=true, [9584]=true, [928]=true, [5497]=true, [11017]=true, [4217]=true,
    [5938]=true, [2485]=true, [5150]=true, [5958]=true, [4210]=true, [4204]=true, [13084]=true, [3494]=true, [4576]=true, [4773]=true, [3026]=true, [3354]=true, [3007]=true, [2489]=true,
    [4156]=true, [1470]=true, [6286]=true, [2627]=true, [1231]=true, [4578]=true, [4753]=true, [7868]=true, [5499]=true, [2834]=true, [2818]=true, [5144]=true, [2329]=true, [7866]=true,
    [1430]=true, [4772]=true, [3067]=true, [4591]=true, [3690]=true, [2798]=true, [3355]=true, [4254]=true, [6018]=true, [8738]=true, [5479]=true, [918]=true, [5137]=true, [5564]=true,
    [4163]=true, [7869]=true, [1103]=true, [5566]=true, [7867]=true, [3347]=true, [4568]=true, [3009]=true, [3032]=true, [3181]=true, [5164]=true, [5517]=true, [1215]=true, [4146]=true,
    [13417]=true, [7871]=true, [3033]=true, [914]=true, [5493]=true, [3064]=true, [3363]=true, [1701]=true, [5480]=true, [2492]=true, [5491]=true, [6292]=true, [8144]=true, [1300]=true,
    [3601]=true, [3602]=true, [6289]=true, [3401]=true, [5511]=true, [5957]=true, [4218]=true, [14740]=true, [913]=true, [5943]=true, [4606]=true, [5885]=true, [908]=true, [4586]=true,
    [6295]=true, [1632]=true, [7954]=true, [5127]=true, [3154]=true, [1651]=true, [3357]=true, [1226]=true, [3607]=true, [3001]=true, [5515]=true, [11031]=true, [6297]=true, [5941]=true,
    [4616]=true, [1382]=true, [377]=true, [1681]=true, [3404]=true, [3175]=true, [10089]=true, [5880]=true, [6387]=true, [2837]=true, [11177]=true, [2391]=true, [8306]=true, [4552]=true,
    [11037]=true, [5506]=true, [5498]=true, [3345]=true, [1411]=true, [5177]=true, [5392]=true, [3344]=true, [514]=true, [10993]=true, [328]=true, [8308]=true, [3596]=true, [5153]=true,
    [2879]=true, [3332]=true, [7089]=true, [11096]=true, [3171]=true, [11068]=true, [11178]=true, [3087]=true, [3039]=true, [3173]=true, [3523]=true, [1355]=true, [5157]=true, [11406]=true,
    [5504]=true, [5939]=true, [1385]=true, [3365]=true, [13283]=true, [8128]=true, [3706]=true, [5171]=true, [10088]=true, [4598]=true, [3594]=true, [3327]=true, [11146]=true, [3605]=true,
    [1700]=true, [5484]=true, [6094]=true, [2132]=true, [1699]=true, [5165]=true, [12030]=true, [3184]=true, [3066]=true, [5496]=true, [895]=true, [5516]=true, [7953]=true, [8140]=true,
    [927]=true, [3136]=true, [5161]=true, [3599]=true, [1241]=true, [4215]=true, [1232]=true, [7232]=true, [986]=true, [1234]=true, [3170]=true, [917]=true, [3964]=true, [3062]=true,
    [3044]=true, [3169]=true, [1703]=true, [3967]=true, [460]=true, [4595]=true, [3172]=true, [4609]=true, [2367]=true, [3174]=true, [6288]=true, [4138]=true, [5501]=true, [3063]=true,
    [3597]=true, [944]=true, [5759]=true, [11401]=true, [4213]=true, [2857]=true, [6290]=true, [2131]=true, [3603]=true, [957]=true, [4584]=true, [3324]=true, [376]=true, [915]=true,
    [3484]=true, [3013]=true, [3031]=true, [3041]=true, [11029]=true, [4588]=true, [1702]=true, [3963]=true, [6299]=true, [461]=true, [4205]=true, [11081]=true, [4219]=true, [7087]=true,
    [3036]=true, [3325]=true, [11397]=true, [3030]=true, [3011]=true, [5172]=true, [5489]=true, [10086]=true, [5145]=true, [3328]=true, [3549]=true, [5502]=true, [4089]=true, [1383]=true,
    [912]=true, [10266]=true, [11046]=true, [3047]=true, [4087]=true, [4573]=true, [3290]=true, [3353]=true, [3179]=true, [4596]=true, [1473]=true, [3306]=true, [3137]=true, [3185]=true,
    [5146]=true, [3688]=true, [7230]=true, [916]=true, [2326]=true, [11065]=true, [812]=true, [5149]=true, [2129]=true, [459]=true, [4214]=true, [3620]=true, [2124]=true, [198]=true,
    [1228]=true, [5884]=true, [3604]=true, [4614]=true, [11071]=true, [11025]=true, [2878]=true, [8146]=true, [3595]=true, [3048]=true, [5695]=true, [3065]=true, [5173]=true, [3593]=true,
    [2856]=true, [4090]=true, [10090]=true, [7946]=true, [4582]=true, [3069]=true, [11083]=true, [5883]=true, [2114]=true, [4607]=true, [5612]=true, [1229]=true, [4091]=true, [3028]=true,
    [2998]=true, [3600]=true, [8153]=true, [5116]=true, [10276]=true, [3403]=true, [2855]=true, [6014]=true, [4900]=true, [4605]=true, [5148]=true, [837]=true, [8141]=true, [5115]=true,
    [3046]=true, [10277]=true, [11066]=true, [4566]=true, [3038]=true, [5492]=true, [7231]=true, [1901]=true, [5113]=true, [3703]=true, [911]=true, [12032]=true, [12025]=true, [4159]=true,
    [543]=true, [375]=true, [3157]=true, [3004]=true, [3606]=true, [2390]=true, [4608]=true, [5167]=true, [3557]=true, [4563]=true, [3707]=true, [1404]=true, [3598]=true, [2130]=true,
    [906]=true, [4583]=true, [11041]=true, [4567]=true, [5117]=true, [3155]=true, [3042]=true, [3034]=true, [3407]=true, [11026]=true, [11050]=true, [3326]=true, [3698]=true, [4898]=true,
    [926]=true, [925]=true, [2128]=true, [4593]=true, [3545]=true, [5690]=true, [3153]=true, [9465]=true, [8142]=true, [988]=true, [12961]=true, [3061]=true, [1680]=true, [2126]=true,
    [3156]=true, [5143]=true, [3478]=true, [5147]=true, [11051]=true, [5784]=true, [3406]=true, [7949]=true, [4594]=true, [3965]=true, [223]=true, [2119]=true, [10930]=true, [1676]=true,
    [3622]=true, [4193]=true, [3059]=true, [3043]=true, [11047]=true, [11070]=true, [3045]=true, [5166]=true, [2127]=true, [5500]=true, [5505]=true, [11048]=true, [1246]=true, [3408]=true,
    [4320]=true, [7315]=true, [3060]=true, [1466]=true, [11028]=true, [5811]=true, [4092]=true, [4564]=true, [3704]=true, [11067]=true, [11049]=true, [11042]=true, [11084]=true, [5141]=true,
    [3040]=true, [5495]=true, [1683]=true, [5994]=true, [3624]=true, [5114]=true, [5142]=true, [2123]=true, [2122]=true, [7312]=true, [11044]=true, [3555]=true, [331]=true, [3008]=true,
    [985]=true, [987]=true, [5882]=true, [4565]=true, [1458]=true, [10278]=true, [3049]=true, [29]=true, [2805]=true, [13476]=true, [3955]=true, [12919]=true, [844]=true, [2664]=true,
    [2685]=true, [8125]=true, [8137]=true, [1312]=true, [8139]=true, [3323]=true, [66]=true, [12944]=true, [12022]=true, [1448]=true, [1257]=true, [2626]=true, [12033]=true, [7947]=true,
    [11189]=true, [2480]=true, [340]=true, [14921]=true, [10667]=true, [4561]=true, [1243]=true, [4229]=true, [4169]=true, [4897]=true, [5494]=true, [14754]=true, [1285]=true, [7775]=true,
    [222]=true, [12245]=true, [3410]=true, [12246]=true, [9499]=true, [16015]=true, [14846]=true, [1286]=true, [5940]=true, [5110]=true, [3369]=true, [11278]=true, [8145]=true, [4173]=true,
    [5132]=true, [5175]=true, [4877]=true, [1307]=true, [1441]=true, [734]=true, [4890]=true, [11536]=true, [2810]=true, [3313]=true, [2679]=true, [5519]=true, [4230]=true, [11557]=true,
    [5594]=true, [3482]=true, [1351]=true, [11188]=true, [14624]=true, [1321]=true, [3614]=true, [4453]=true, [4165]=true, [12942]=true, [7852]=true, [1303]=true, [3556]=true, [8361]=true,
    [13699]=true, [15419]=true, [13698]=true, [1297]=true, [12943]=true, [2670]=true, [1465]=true, [3335]=true, [5942]=true, [7564]=true, [2832]=true, [6777]=true, [5754]=true, [4730]=true,
    [2482]=true, [5817]=true, [4585]=true, [5816]=true, [2381]=true, [11056]=true, [3539]=true, [5133]=true, [3027]=true, [3334]=true, [3490]=true, [14753]=true, [3362]=true, [10857]=true,
    [11185]=true, [5101]=true, [2118]=true, [10856]=true, [12941]=true, [3348]=true, [5162]=true, [7976]=true, [3537]=true, [3881]=true, [13219]=true, [4085]=true, [3935]=true, [3562]=true,
    [2821]=true, [3534]=true, [3658]=true, [1148]=true, [3413]=true, [4086]=true, [4878]=true, [15174]=true, [2848]=true, [2803]=true, [4217]=true, [16376]=true, [2687]=true, [3133]=true,
    [15179]=true, [4610]=true, [7978]=true, [10618]=true, [2622]=true, [2682]=true, [1298]=true, [4574]=true, [4879]=true, [9087]=true, [1302]=true, [3015]=true, [2699]=true, [3342]=true,
    [4083]=true, [4305]=true, [8666]=true, [13217]=true, [15293]=true, [11057]=true, [4981]=true, [225]=true, [8679]=true, [1460]=true, [3409]=true, [2481]=true, [11187]=true, [7854]=true,
    [4226]=true, [9636]=true, [1313]=true, [3319]=true, [4182]=true, [3495]=true, [3164]=true, [6576]=true, [12043]=true, [12959]=true, [6779]=true, [3954]=true, [4590]=true, [3529]=true,
    [1275]=true, [1287]=true, [1323]=true, [12799]=true, [9544]=true, [2672]=true, [1304]=true, [3956]=true, [167]=true, [3960]=true, [14322]=true, [5188]=true, [1289]=true, [6548]=true,
    [12805]=true, [1261]=true, [1146]=true, [5128]=true, [1319]=true, [3180]=true, [4891]=true, [3322]=true, [5120]=true, [6301]=true, [2483]=true, [3497]=true, [7955]=true, [10118]=true,
    [8160]=true, [3314]=true, [1291]=true, [483]=true, [384]=true, [14637]=true, [4220]=true, [14437]=true, [6929]=true, [8157]=true, [3361]=true, [3489]=true, [2393]=true, [8307]=true,
    [3368]=true, [2698]=true, [4307]=true, [894]=true, [8364]=true, [3488]=true, [4170]=true, [3134]=true, [15127]=true, [2397]=true, [1325]=true, [8118]=true, [1694]=true, [3081]=true,
    [1347]=true, [5160]=true, [3018]=true, [1247]=true, [3550]=true, [2684]=true, [3366]=true, [1669]=true, [4232]=true, [6735]=true, [4225]=true, [8665]=true, [11038]=true, [4569]=true,
    [4575]=true, [8122]=true, [1691]=true, [15471]=true, [1299]=true, [15176]=true, [12957]=true, [12777]=true, [6746]=true, [1149]=true, [1309]=true, [7952]=true, [2816]=true, [3498]=true,
    [2383]=true, [277]=true, [13216]=true, [11555]=true, [9179]=true, [6730]=true, [3561]=true, [1682]=true, [3017]=true, [2688]=true, [12384]=true, [1250]=true, [5483]=true, [5111]=true,
    [2380]=true, [491]=true, [3499]=true, [5193]=true, [15126]=true, [3541]=true, [5178]=true, [4617]=true, [3168]=true, [5565]=true, [14740]=true, [8305]=true, [5411]=true, [11874]=true,
    [4592]=true, [3333]=true, [4562]=true, [6568]=true, [4604]=true, [7683]=true, [989]=true, [8158]=true, [3685]=true, [4241]=true, [4265]=true, [4782]=true, [3492]=true, [3546]=true,
    [12782]=true, [5151]=true, [1318]=true, [2843]=true, [2819]=true, [8131]=true, [5123]=true, [4555]=true, [11116]=true, [1454]=true, [5158]=true, [4203]=true, [6740]=true, [12792]=true,
    [14847]=true, [12958]=true, [13218]=true, [8161]=true, [3542]=true, [5783]=true, [1684]=true, [5122]=true, [4731]=true, [4884]=true, [4894]=true, [7744]=true, [5757]=true, [3135]=true,
    [1459]=true, [14450]=true, [1326]=true, [5124]=true, [2806]=true, [12021]=true, [233]=true, [3367]=true, [3493]=true, [3962]=true, [4589]=true, [3025]=true, [2683]=true, [2663]=true,
    [4235]=true, [3682]=true, [12956]=true, [6367]=true, [5100]=true, [3186]=true, [5815]=true, [1671]=true, [2394]=true, [2357]=true, [3543]=true, [3029]=true, [4194]=true, [777]=true,
    [4602]=true, [2839]=true, [6738]=true, [1456]=true, [8362]=true, [3958]=true, [8178]=true, [3317]=true, [14522]=true, [1668]=true, [151]=true, [1453]=true, [6731]=true, [6807]=true,
    [5814]=true, [3346]=true, [3005]=true, [8878]=true, [4556]=true, [1348]=true, [11106]=true, [4200]=true, [3548]=true, [4175]=true, [3554]=true, [4896]=true, [8934]=true, [7940]=true,
    [2812]=true, [4256]=true, [10216]=true, [3316]=true, [295]=true, [8150]=true, [4553]=true, [5821]=true, [5520]=true, [1263]=true, [3608]=true, [14480]=true, [3481]=true, [3097]=true,
    [958]=true, [14481]=true, [4184]=true, [843]=true, [8401]=true, [6382]=true, [1301]=true, [2840]=true, [2084]=true, [829]=true, [2846]=true, [3162]=true, [2697]=true, [3578]=true,
    [3091]=true, [960]=true, [3536]=true, [5049]=true, [5107]=true, [4571]=true, [3684]=true, [1685]=true, [3405]=true, [1673]=true, [3364]=true, [2838]=true, [3577]=true, [14860]=true,
    [1692]=true, [5155]=true, [4892]=true, [8403]=true, [8678]=true, [12783]=true, [11184]=true, [8359]=true, [14301]=true, [3019]=true, [4167]=true, [9501]=true, [6747]=true, [6791]=true,
    [7772]=true, [2401]=true, [3360]=true, [5848]=true, [5753]=true, [3044]=true, [3479]=true, [7879]=true, [14581]=true, [14371]=true, [10369]=true, [11287]=true, [4236]=true, [1463]=true,
    [3095]=true, [4886]=true, [6930]=true, [1471]=true, [1237]=true, [4557]=true, [1322]=true, [5108]=true, [12796]=true, [3609]=true, [5812]=true, [3074]=true, [5611]=true, [1687]=true,
    [1238]=true, [5103]=true, [5170]=true, [7737]=true, [2388]=true, [3683]=true, [15898]=true, [4888]=true, [13018]=true, [5510]=true, [983]=true, [3592]=true, [3350]=true, [274]=true,
    [9548]=true, [4216]=true, [2668]=true, [15197]=true, [190]=true, [10293]=true, [7942]=true, [14337]=true, [2908]=true, [4885]=true, [1147]=true, [11118]=true, [5698]=true, [2997]=true,
    [15175]=true, [3351]=true, [4186]=true, [4177]=true, [6495]=true, [1457]=true, [3518]=true, [1469]=true, [8129]=true, [1316]=true, [3096]=true, [4587]=true, [12097]=true, [3589]=true,
    [227]=true, [5819]=true, [226]=true, [5109]=true, [8681]=true, [2849]=true, [4597]=true, [3187]=true, [3953]=true, [1214]=true, [4172]=true, [4234]=true, [3951]=true, [11183]=true,
    [9549]=true, [3611]=true, [5106]=true, [12960]=true, [54]=true, [4180]=true, [5503]=true, [8360]=true, [981]=true, [3934]=true, [8931]=true, [12023]=true, [2814]=true, [3012]=true,
    [8177]=true, [1695]=true, [2669]=true, [12096]=true, [3178]=true, [12027]=true, [5169]=true, [4899]=true, [4228]=true, [1294]=true, [4191]=true, [5163]=true, [956]=true, [836]=true,
    [12795]=true, [4223]=true, [4181]=true, [8176]=true, [3165]=true, [3000]=true, [11703]=true, [1273]=true, [8508]=true, [10361]=true, [5138]=true, [14964]=true, [1324]=true, [3088]=true,
    [7714]=true, [7733]=true, [3610]=true, [4231]=true, [3359]=true, [3970]=true, [4577]=true, [12026]=true, [9553]=true, [2136]=true, [3530]=true, [1198]=true, [3356]=true, [5189]=true,
    [4560]=true, [3400]=true, [3572]=true, [5173]=true, [228]=true, [2116]=true, [5125]=true, [1310]=true, [2845]=true, [3090]=true, [1333]=true, [6928]=true, [12196]=true, [6741]=true,
    [5688]=true, [4876]=true, [3072]=true, [13435]=true, [5748]=true, [4883]=true, [1295]=true, [5758]=true, [3587]=true, [3330]=true, [4603]=true, [1645]=true, [17598]=true, [10380]=true,
    [7945]=true, [1320]=true, [8363]=true, [1350]=true, [4889]=true, [15864]=true, [896]=true, [15011]=true, [2842]=true, [12962]=true, [3485]=true, [9552]=true, [3552]=true, [2046]=true,
    [5152]=true, [1450]=true, [2365]=true, [6028]=true, [5102]=true, [3020]=true, [5569]=true, [4601]=true, [5820]=true, [3085]=true, [12807]=true, [1452]=true, [12045]=true, [7943]=true,
    [4187]=true, [6736]=true, [3700]=true, [3483]=true, [16256]=true, [954]=true, [4615]=true, [5749]=true, [3937]=true, [1339]=true, [3076]=true, [3321]=true, [9555]=true, [14739]=true,
    [2364]=true, [3014]=true, [13420]=true, [15354]=true, [4581]=true, [1407]=true, [9551]=true, [3023]=true, [14844]=true, [3779]=true, [3500]=true, [1650]=true, [9676]=true, [3163]=true,
    [2808]=true, [4222]=true, [11137]=true, [8404]=true, [465]=true, [12793]=true, [4255]=true, [152]=true, [4266]=true, [1462]=true, [3003]=true, [4043]=true, [14963]=true, [4600]=true,
    [1362]=true, [3291]=true, [980]=true, [1104]=true, [3486]=true, [3477]=true, [1464]=true, [6272]=true, [11103]=true, [6790]=true, [13430]=true, [790]=true, [5121]=true, [6027]=true,
    [3621]=true, [14961]=true, [3533]=true, [15315]=true, [3625]=true, [15199]=true, [4185]=true, [9099]=true, [984]=true, [3079]=true, [10364]=true, [1349]=true, [1315]=true, [4240]=true,
    [6328]=true, [12019]=true, [14962]=true, [1314]=true, [3158]=true, [2140]=true, [6300]=true, [6567]=true, [1213]=true, [3358]=true, [2117]=true, [5119]=true, [2265]=true, [2264]=true,
    [12776]=true, [2352]=true, [6727]=true, [7731]=true, [9356]=true, [2847]=true, [5512]=true, [793]=true, [3021]=true, [3331]=true, [15353]=true, [13418]=true, [1697]=true, [1381]=true,
    [5870]=true, [5139]=true, [3159]=true, [12028]=true, [4257]=true, [4558]=true, [791]=true, [12781]=true, [5190]=true, [1670]=true, [3480]=true, [2134]=true, [11182]=true, [3312]=true,
    [1308]=true, [3532]=true, [4599]=true, [3553]=true, [5508]=true, [5135]=true, [4570]=true, [4221]=true, [4554]=true, [4559]=true, [4195]=true, [3177]=true, [3349]=true, [4189]=true,
    [13433]=true, [2135]=true, [2113]=true, [2366]=true, [5514]=true, [5570]=true, [4084]=true, [4164]=true, [6091]=true, [3411]=true, [15006]=true, [5140]=true, [2137]=true, [1328]=true,
    [3969]=true, [3298]=true, [3705]=true, [13436]=true, [5112]=true, [3933]=true, [8152]=true, [8358]=true, [3160]=true, [4188]=true, [6739]=true, [6734]=true, [6737]=true, [1686]=true,
    [3491]=true, [3590]=true, [15012]=true, [2115]=true, [258]=true, [3487]=true, [372]=true, [5509]=true, [3078]=true, [3329]=true, [74]=true, [4190]=true, [5871]=true, [8143]=true,
    [13434]=true, [12031]=true, [3961]=true, [7941]=true, [3613]=true, [3531]=true, [959]=true, [1461]=true, [13429]=true, [7485]=true, [12029]=true, [8398]=true, [5126]=true, [14738]=true,
    [3551]=true, [3528]=true, [1474]=true, [3161]=true, [955]=true, [12785]=true, [3089]=true, [14737]=true, [12794]=true, [3053]=true, [3092]=true, [3016]=true, [15124]=true, [2999]=true,
    [6298]=true, [982]=true, [4259]=true, [4954]=true, [1678]=true, [6376]=true, [8116]=true, [3882]=true, [3952]=true, [6496]=true, [3075]=true, [3166]=true, [6373]=true, [1296]=true,
    [1698]=true, [3591]=true, [5750]=true, [2820]=true, [3343]=true, [3093]=true, [5886]=true, [3547]=true, [3948]=true, [16458]=true, [1305]=true, [3544]=true, [8121]=true, [3884]=true,
    [1311]=true, [5134]=true, [3588]=true, [3002]=true, [3689]=true, [12784]=true, [5129]=true, [1672]=true, [4580]=true, [2303]=true, [5156]=true, [3010]=true, [3073]=true, [12024]=true,
    [3883]=true, [3959]=true, [5154]=true, [945]=true, [3138]=true, [13432]=true, [5191]=true, [3612]=true, [3022]=true, [4192]=true, [3315]=true, [4875]=true, [8117]=true, [3167]=true,
    [5944]=true, [2225]=true, [10379]=true, [4893]=true, [5620]=true, [1240]=true, [3522]=true, [6374]=true, [4168]=true, [4775]=true, [4082]=true, [3086]=true, [3708]=true, [3540]=true,
    [3080]=true, [2844]=true, [78]=true, [6574]=true, [789]=true, [15125]=true, [14731]=true, [11186]=true, [3077]=true, [4171]=true, [4233]=true, [4183]=true, [1249]=true, [10367]=true,
    [14845]=true, [1690]=true, [13431]=true, [1341]=true, [8159]=true, [20]=true, [14981]=true, [907]=true, [14982]=true, [7427]=true, [12197]=true, [5118]=true, [347]=true, [15007]=true,
    [7410]=true, [3890]=true, [15106]=true, [10360]=true, [14990]=true, [15006]=true, [15008]=true, [15102]=true, [2302]=true, [857]=true, [2804]=true, [14991]=true, [15103]=true, [15105]=true,
    [14942]=true, [12198]=true,
}

-- ============================================================
-- MUTE TABLES - fileDataIDs handed to MuteSoundFile. Key names match
-- the Leatrix children so his choices carry straight over.
-- ============================================================
QoL.MUTE_GAME = {
    MuteChimes = {
        566564, 565853, 566558, 566027, 566064,
    },
    MuteFizzle = {
        569773, 569775, 569772, 569774, 569776,
    },
    MuteInterface = {
        567481, 567407, 567464, 567490,
    },
    MuteTrains = {
        539802, 539881, 540271, 540275, 540535, 540734, 540870,
        540947, 541157, 541239, 542818, 542896, 543085, 543093,
        542526, 542600,
    },
    MuteScreech = {
        569429,
    },
    MuteYawns = {
        562388,
    },
    MuteReady = {
        567478, 567409,
    },
    MutePiccolo = {
        568271,
    },
}

-- MuteLogin is the odd one out: the main theme (53223) is muted at
-- LOGOUT and unmuted at login, so the login screen sound only dies on
-- the way out - exactly the Leatrix trick.
QoL.MUTE_LOGOUT = { 53223 }

QoL.MUTE_MOUNT = {
    MuteMechSteps = {
        550507, 550514, 550501, 550500, 550511, 550504, 550498,
    },
    MuteStriders = {
        555127, 555125, 555123, 555132, 555124, 555128, 555129,
        555130, 555131,
    },
    MuteHorsesteps = {
        552083, 552081, 552072, 552089, 552078, 552087, 552085,
        552062, 552071, 552079, 552065, 552084, 552058, 552073,
        552077, 552090, 552068, 552070, 552082, 552060, 552086,
        552075, 552076, 552066, 552063,
    },
}

-- shared with later ZacUI files
ns.QoL = QoL
