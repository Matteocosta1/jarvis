import Foundation
import Photos

/// 4 nov · le parole della ricerca in Foto. Prima la ricerca capiva una trentina di parole e alcune non esistevano tra le categorie
/// di Apple («vinile», «dischi», «selfie»), i plurali non c'erano e si confrontavano pezzi di parola («cane» trovava gli hot dog).
/// Ora: il dizionario italiano completo delle 1.303 categorie che l'AI di Apple (Vision) riconosce nelle foto, con i plurali e i
/// sinonimi più usati, più le parole inglesi della tassonomia; si confrontano parole intere. Alcune parole sono album di Apple
/// (selfie, screenshot, preferite, ritratti, panoramiche, raffiche, lunghe esposizioni). Solo calcoli: senza attore.
nonisolated enum DizionarioFoto {
    /// Una cosa da cercare: una o più categorie di Vision (basta una), oppure un album di Apple (il tipo, come numero).
    nonisolated enum Cosa: Hashable, Sendable {
        case etichette(Set<UInt16>)
        case album(Int)
    }

    /// Le 1.303 categorie di Vision (VNClassifyImageRequest, revisione 1), nell'ordine di Apple.
    static let etichette: [String] = elenco.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

    /// Il numero di ogni categoria (così l'indice delle foto tiene due byte per etichetta).
    static let posizione: [String: UInt16] = {
        var p: [String: UInt16] = [:]
        for (k, e) in etichette.enumerated() { p[e] = UInt16(k) }
        return p
    }()

    /// Parola o frase italiana (o sinonimo inglese) → categorie: «cane» → dog, canine; «mare» → ocean, beach, shore, water_body.
    private static let parole: [String: Set<UInt16>] = {
        var m: [String: Set<UInt16>] = [:]
        for riga in (dati + "\n" + datiInglesi).split(separator: "\n") {
            let pezzi = riga.split(separator: "|", maxSplits: 1)
            guard pezzi.count == 2, let k = posizione[pezzi[0].trimmingCharacters(in: .whitespaces)] else { continue }
            for termine in pezzi[1].split(separator: ",") {
                for forma in termine.split(separator: "/") {
                    let chiave = normalizza(String(forma)).joined(separator: " ")
                    if !chiave.isEmpty { m[chiave, default: []].insert(k) }
                }
            }
        }
        return m
    }()

    /// Le parti delle categorie inglesi: «sunset» in «sunset_sunrise», «cat» in «adult_cat».
    private static let parti: [String: Set<UInt16>] = {
        var m: [String: Set<UInt16>] = [:]
        for (k, e) in etichette.enumerated() {
            for p in e.split(separator: "_") { m[String(p), default: []].insert(UInt16(k)) }
        }
        return m
    }()

    /// Le parole che sono album di Apple (più precisi dell'AI per queste cose).
    private static let albumSpeciali: [String: Int] = {
        var m: [String: Int] = [:]
        let gruppi: [(PHAssetCollectionSubtype, [String])] = [
            (.smartAlbumSelfPortraits, ["selfie", "selfies", "autoscatto", "autoscatti"]),
            (.smartAlbumScreenshots, ["screenshot", "screenshots", "schermata", "schermate"]),
            (.smartAlbumFavorites, ["preferita", "preferite", "preferito", "preferiti", "favorite", "favorites"]),
            (.smartAlbumDepthEffect, ["ritratto", "ritratti", "modalita ritratto", "portrait", "portraits"]),
            (.smartAlbumPanoramas, ["panoramica", "panoramiche", "panoramic"]),
            (.smartAlbumBursts, ["raffica", "raffiche", "burst"]),
            (.smartAlbumLongExposures, ["lunga esposizione", "lunghe esposizioni", "long exposure"]),
        ]
        for (tipo, nomi) in gruppi { for n in nomi { m[n] = tipo.rawValue } }
        return m
    }()

    /// Le parole che non cambiano la ricerca (articoli, preposizioni, «foto», «mie»…).
    private static let vuote: Set<String> = [
        "il", "lo", "la", "i", "gli", "le", "l", "un", "uno", "una", "d", "di", "del", "dello", "della", "dei", "degli", "delle",
        "dell", "da", "dal", "dallo", "dalla", "dai", "dagli", "dalle", "dall", "a", "ad", "al", "allo", "alla", "ai", "agli", "alle",
        "all", "in", "nel", "nello", "nella", "nei", "negli", "nelle", "nell", "su", "sul", "sullo", "sulla", "sui", "sugli", "sulle",
        "sull", "con", "col", "coi", "per", "tra", "fra", "e", "ed", "o", "od", "c", "ci", "che", "dove", "quando",
        "foto", "fotografia", "fotografie", "immagine", "immagini", "mie", "miei", "mia", "mio",
        "the", "of", "an", "and", "with", "on", "at", "photo", "photos", "picture", "pictures",
    ]

    /// Minuscole, senza accenti né punteggiatura, senza le parole vuote: «Torta di Compleanno!» → ["torta", "compleanno"].
    static func normalizza(_ s: String) -> [String] {
        let f = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "it_IT"))
        var pulito = String.UnicodeScalarView()
        for c in f.unicodeScalars { pulito.append(CharacterSet.alphanumerics.contains(c) ? c : " ") }
        return String(pulito).split(separator: " ").map { String($0) }.filter { !vuote.contains($0) }
    }

    /// Le cose da cercare in un testo (la frase più lunga che si riconosce, fino a 4 parole) e le parole che non si riconoscono.
    static func capisci(_ testo: String) -> (cose: [Cosa], nonCapite: [String]) {
        let w = normalizza(testo)
        var cose: [Cosa] = [], ignote: [String] = []
        var i = 0
        while i < w.count {
            var presa = 0
            for l in stride(from: min(4, w.count - i), through: 1, by: -1) {
                let k = w[i..<(i + l)].joined(separator: " ")
                if let a = albumSpeciali[k] { cose.append(.album(a)); presa = l; break }
                if let e = parole[k] { cose.append(.etichette(e)); presa = l; break }
                if let e = inglese(k) { cose.append(.etichette(e)); presa = l; break }
            }
            if presa == 0 { ignote.append(w[i]); i += 1 } else { i += presa }
        }
        return (cose, ignote)
    }

    /// Una parola (o frase) inglese della tassonomia: la categoria intera («ice cream» = ice_cream), una sua parte («sunset»), o il
    /// suo plurale («dogs»).
    private static func inglese(_ k: String) -> Set<UInt16>? {
        if let p = posizione[k.replacingOccurrences(of: " ", with: "_")] { return [p] }
        guard !k.contains(" ") else { return nil }
        if let p = parti[k] { return p }
        if k.hasSuffix("ies"), let p = parti[String(k.dropLast(3)) + "y"] { return p }
        if k.hasSuffix("es"), let p = parti[String(k.dropLast(2))] { return p }
        if k.hasSuffix("s"), let p = parti[String(k.dropLast())] { return p }
        return nil
    }

    /// Le 1.303 categorie, come le dà Apple.
    private static let elenco = """
        abacus, accordion, acorn, acrobat, adult, adult_cat, agriculture, aircraft, airplane, airport,
        airshow, alley, alligator_crocodile, almond, ambulance, amusement_park, anchovy, angelfish, animal, ant,
        antipasti, anvil, apartment, apple, appliance, apricot, apron, aquarium, arachnid, arch,
        archery, arena, armchair, art, arthropods, artichoke, arugula, asparagus, athletics, atm,
        atv, auditorium, aurora, australian_shepherd, automobile, avocado, axe, baby, backgammon, backhoe,
        backpack, bacon, badminton, bag, bagel, baked_goods, baklava, balcony, ball, ballet,
        ballet_dancer, ballgames, balloon, balloon_hotair, banana, banner, bar, barbell, barge, barn,
        barnacle, barracuda, barrel, baseball, baseball_bat, baseball_hat, basenji, basket_container, basketball, basset,
        bath, bathrobe, bathroom, bathroom_faucet, bathroom_room, beach, beagle, bean, beanie, bear,
        bed, bedding, bedroom, bee, beef, beehive, beekeeping, beer, beet, begonia,
        bell, bell_pepper, belltower, bellydance, bench, bernese_mountain, berry, bib, bichon, bicycle,
        billboards, billiards, binoculars, bird, birdhouse, birthday_cake, biryani, biscotti, biscuit, bison,
        blackberry, bleachers, blender, blizzard, blocks, blossom, blue_sky, blueberry, boar, board_game,
        boat, boathouse, bobcat, bodyboard, bongo_drum, bonsai, book, bookshelf, boot, bottle,
        bouquet, bowl, bowling, bowtie, boxing, branch, brass_music, bread, breakdancing, brick,
        brick_oven, bride, bridesmaid, bridge, briefcase, broccoli, broom, brownie, bruschetta, bubble_tea,
        bucket, building, bulldog, bulldozer, bullfighting, bungee, burrito, bus, butter, butterfly,
        cabinet, cableway, cactus, cage, cake, cake_regular, cakestand, calculator, calendar, caliper,
        camel, camera, camping, candle, candlestick, candy, candy_cane, candy_other, canine, canoe,
        cantaloupe, canyon, caprese, car, car_seat, caramel, cardboard_box, carnation, carnival, carousel,
        carrot, cart, carton, cashew, casino, casserole, cassette, castle, cat, caterpillar,
        cauliflower, cave, cd, celebration, celery, celestial_body, celestial_body_other, cellar, cello, centipede,
        cephalopod, cereal, ceremony, cetacean, chainsaw, chair, chair_other, chairlift, chaise, chalkboard,
        chameleon, chandelier, chart, checkbook, cheerleading, cheese, cheesecake, cheetah, cherry, chess,
        chestnut, chewing_gum, chihuahua, child, chimney, chinchilla, chives, chocolate, chocolate_chip, chopsticks,
        christmas_decoration, christmas_tree, chrysanthemum, cigar, cigarette, cilantro, circuit_board, circus, citrus_fruit, cityscape,
        clam, clarinet, classroom, cliff, cloak, clock, clock_tower, closet, clothesline, clothespin,
        clothing, cloudy, clover, clown, clownfish, cockatoo, cocktail, coconut, coffee, coffee_bean,
        coin, coleslaw, collie, compass, computer, computer_keyboard, computer_monitor, computer_mouse, computer_tower, concert,
        conch, condiment, conference, consumer_electronics, container, convertible, conveyance, cookie, cookware, coral_reef,
        cord, corgi, corkscrew, corn, cornflower, cosmetic_tool, costume, cougar, coupon, cow,
        cowboy_hat, coyote_wolf, crab, cranberry, crane_construction, crate, credit_card, creek, crepe, crib,
        cricket_sport, croissant, crosswalk, crowd, cruise_ship, crutch, cubicle, cucumber, cup, cupcake,
        currency, curry, curtain, cutting_board, cycling, dachshund, daffodil, dahlia, daikon, daisy,
        dalmatian, dam, dancing, dandelion, dartboard, dashboard, daytime, decanter, deck, decoration,
        decorative_plant, deejay, deer, desert, desk, dessert, diagram, dial, diaper, dice,
        dill, dining_room, dinosaur, diorama, dirt_road, disco_ball, dishwasher, diskette, diving, doberman,
        dock, document, dog, doll, dolphin, dome, domicile, domino, donkey, donut,
        door, dove, dragon_parade, dragonfly, dressage, drink, drinking_glass, driveway, drone_machine, drum,
        dumbbell, dumpling, durian, eagle, earmuffs, easel, easter_egg, edamame, egg, eggplant,
        electric_fan, elephant, elevator, elk, embers, engine_vehicle, entertainer, envelope, equestrian, escalator,
        eucalyptus_tree, evergreen, extinguisher, eyeglasses, fairground, falafel, farm, fedora, feline, fence,
        fencing_sport, ferns, ferret, ferris_wheel, fig, figurine, fire, firecracker, fireplace, firetruck,
        fireworks, fish, fishbowl, fishing, fishtank, flag, flagpole, flame, flamingo, flan,
        flashlight, flipchart, flipper, flower, flower_arrangement, flute, folding_chair, foliage, fondue, food,
        foosball, football, footwear, forest, fork, forklift, formula_one_car, fountain, fox, frame,
        fried_chicken, fried_egg, fries, frisbee, frog, frozen, frozen_dessert, fruit, fruitcake, furniture,
        gamepad, games, garage, garden, gargoyle, garlic, gas_mask, gastropod, gazebo, gears,
        gecko, gerbil, german_shepherd, geyser, gift, gift_card, gingerbread, giraffe, glacier, glove,
        glove_other, go_kart, goat, goggles, goldfish, golf, golf_ball, golf_club, golf_course, gown,
        graduation, graffiti, grain, grand_prix, grape, grapefruit, grass, grater, grave, green_beans,
        greenhouse, greyhound, grill, grilled_chicken, groom, guacamole, guava, guitar, gull, guppy,
        gymnastics, gyoza, habanero, ham, hamburger, hammer, hammock, hamster, handwriting, hangar,
        hangglider, harbour, hardhat, harp, hat, haze, headgear, headphones, health_club, hedgehog,
        helicopter, helmet, henna, herb, heron, high_chair, high_heel, hiking, hill, hippopotamus,
        hockey, holly, honey, honeydew, hoodie, hookah, horse, horseshoe, hospital, hotdog,
        hound, hourglass, house_single, houseboat, housewares, hula, hummingbird, hummus, hunting, hurdle,
        husky, hydrant, hyena, ice, ice_cream, ice_skates, ice_skating, iceberg, igloo, iguana,
        illustrations, insect, interior_room, interior_shop, irish_wolfhound, iron_clothing, island, ivy, jack_o_lantern, jack_russell_terrier,
        jacket, jacuzzi, jalapeno, jar, jeans, jeep, jello, jelly, jellyfish, jetski,
        jewelry, jigsaw, jockey_horse, joystick, jug, juggling, juice, juicer, jungle, kangaroo,
        karaoke, kayak, kebab, keg, kettle, keypad, kickboxing, kilt, kimono, kitchen,
        kitchen_countertop, kitchen_faucet, kitchen_oven, kitchen_room, kitchen_sink, kite, kiteboarding, kitten, kiwi, knife,
        koala, kohlrabi, koi, lab_coat, ladle, ladybug, lake, lamp, lamppost, land,
        lantern, laptop, laundry_machine, lava, leash, leek, lemon, lemongrass, lemur, leopard,
        leotard, lettuce, library, license_plate, lifejacket, lifesaver, light, light_bulb, lighter, lighthouse,
        lightning, lily, lime, limousine, lion, lionfish, liquid, liquor, living_room, lizard,
        llama, loafer, lobster, lollipop, luggage, lychee, lynx, macadamia, machine, mackerel,
        magazine, mailbox, malamute, malinois, mallet, mammal, mandarine, mango, mangosteen, mangrove,
        manhole, map, maple_tree, margarita, marigold, marshmallow, marsupial, martial_arts, martini, mask,
        mast, mastiff, matches, material, matzo, measuring_tape, meat, meatball, medal, media,
        medicine, megalith, megaphone, melon, microphone, microscope, microwave, military_uniform, milkshake, millipede,
        mistletoe, mitten, moccasin, mojito, mollusk, money, monitor_lizard, monorail, monument, moon,
        moose, mop, moss, moth, motocross, motorcycle, motorhome, motorsport, mountain, mousetrap,
        mower, muffin, mug, museum, mushroom, music, musical_instrument, mussel, mustard, naan,
        nachos, nascar, necktie, nectarine, nest, newfoundland, newspaper, night_sky, nightclub, nut,
        oak_tree, oar, oatmeal, obelisk, ocean, office_supplies, omelet, onion, optical_equipment, oranges,
        orchard, orchestra, orchid, organ_instrument, origami, ostrich, otter, outdoor, oven, owl,
        oyster, pacifier, paella, paintball, paintbrush, painting, palm_tree, pan, pancake, panda,
        papaya, paper_bag, parachute, parade, parakeet, parasailing, park, parking_lot, parrot, passionfruit,
        passport, pasta, pastry, path, patio, payphone, pea, peach, peacock, peanut,
        pear, pecan, pelican, pen, penguin, people, pepper_veggie, pepperoni, peregrine, performance,
        pergola, persimmon, petunia, phone, piano, pickle, pie, pier, pierogi, pig,
        pigeon, piggybank, pillow, pineapple, ping_pong, pipe, pistachio, pita, pitbull, pizza,
        plant, plate, play_card, playground, pliers, plum, podium, poinsettia, poker, pole,
        police_car, polka_dots, polo, pomegranate, pomeranian, poncho, poodle, pool, popcorn, popsicle,
        porch, porcupine, portal, porthole, pot_cooking, potato, poultry, power_saw, prairie_dog, pretzel,
        printed_page, printer, propeller, puck, pudding, puffer_fish, puffin, pug, pulley, pumpkin,
        puppet, purse, putt, puzzles, pylon, pyramid, pyrotechnics, python, quesadilla, quinoa,
        rabbit, raccoon, racquet, radish, rafting, railroad, rainbow, rake, rambutan, ramen,
        rangoli, raptor, raspberry, rat, ratchet, rattlesnake, raven, raw_glass, receipt, record,
        recreation, red_envelope, red_wine, refrigerator, reptile, restaurant, retriever, rhinoceros, rhubarb, rice,
        rice_field, rickshaw, ridgeback, rim, rink, risotto, river, road, road_other, road_safety_equipment,
        rock_climbing, rocket, rocks, rodent, rodeo, roe, rollercoaster, rollerskates, rollerskating, rolling_pin,
        roof, rope, rose, rosemary, rotisserie, rottweiler, roulette, rowboat, rugby, ruins,
        sack, saddle, safety_vest, sailboat, saint_bernard, salad, salami, salmon, samba, samosa,
        sand, sand_dune, sandal, sandcastle, sandpiper, sandwich, sangria, santa_claus, sardine, sari,
        satay, sauerkraut, sausage, saxophone, scallop, scarab, scarecrow, scarf, schnauzer, scissors,
        scone, scooter, scoreboard, scorpion, scrambled_eggs, screenshot, screwdriver, scuba, seabass, seafood,
        seahorse, seal, sealion, seashell, seasonings, seat, seaweed, seed, seesaw, semi_truck,
        sequoia, sesame, setter, sewing, shark, shawarma, shed, sheep, sheepdog, shellfish,
        shellfish_prepared, shipyard, shoes, shopping_cart, shore, shower, shrub, sidewalk, sign, silo,
        singer, skateboard, skateboarding, skatepark, skating, skeleton, ski_boot, ski_equipment, skiing, skull,
        skunk, sky, skydiving, skyscraper, sled, sledding, slide_toy, smokestack, smoking_item, smoothie,
        snail, snake, snake_other, snapdragon, snapper, sneaker, snorkeling, snow, snowball, snowboard,
        snowboarding, snowman, snowmobile, snowshoe, soccer, sock, soda, sofa, softball, solar_panel,
        sombrero, souffle, soup, souvlaki, spaghetti, spaniel, spareribs, sparkler, sparkling_wine, sparrow,
        spatula, speakers_music, speedboat, spice, spider, spiderweb, spinach, spoon, sport, sports_equipment,
        sportscar, spotlight, springroll, sprinkler, squash_sport, squirrel, stadium, stained_glass, stairs, starfish,
        starfruit, statue, steak, steamer_cookware, stereo, stethoscope, sticky_note, stingray, stir_fry, stool,
        stopwatch, storefront, stork, storm, stove, straw_drinking, straw_hay, strawberry, street, street_sign,
        streetcar, stretcher, string_instrument, stroller, structure, strudel, stuffed_animals, submarine_water, sugar_cube, suit,
        suitcase, sumo, sun, sunbathing, sundial, sunfish, sunflower, sunflower_seeds, sunglasses, sunhat,
        sunset_sunrise, surfboard, surfing, sushi, suv, swan, swimming, swimsuit, swing_playground, swivel_chair,
        sword, swordfish, syringe, tabbouleh, table, tableware, tachometer, taco, taffy, tambourine,
        tapas, tapioca_pearls, taro, tattoo, tea_drink, teapot, teen, telescope, television, tempura,
        tennis, tent, tequila, teriyaki, terrarium, terrier, textile, theater, thermometer, thermos,
        thermostat, thunderstorm, tiara, ticket, tiger, timepiece, tiramisu, tire, toad, toaster,
        toaster_oven, toilet_seat, tomato, tool, toolbox, tornado, tortilla, tortoise, toucan, tower,
        toy, track_rail, tractor, traffic_light, trail, train, train_real, train_station, train_toy, trampoline,
        tramway, trash_can, treadmill, tree, tricycle, tripod, trombone, trophy, trout, truck,
        trumpet, tuba, tulip, tuna, tunnel, turmeric, turntable, turtle, tuxedo, typewriter,
        ukulele, umbrella, underwater, ungulates, urchin, utensil, vacuum, van, vase, vegetable,
        vegetation, vehicle, vehicle_toy, videogame, vineyard, violin, vizsla, volcano, volleyball, vulture,
        waffle, wagon, wakeboarding, wallet, walrus, warship, wasabi, washbasin, watch, water,
        water_body, watercraft, waterfall, watering_can, watermelon, watermill, waterpolo, watersport, waterways, wedding,
        wedding_cake, wedding_dress, weight_scale, weimaraner, wetland, wetsuit, whale, wheat, wheel, wheelbarrow,
        wheelchair, whisk, white_bread, white_wine, whiteboard, willow, winch, wind_turbine, windmill, window,
        windsurfing, wine, wine_bottle, winter_sport, wonton, wood_natural, wood_processed, woodpecker, woodwind, workout,
        worm, wreath, wrench, wrestling, xylophone, yacht, yarn, yoga, yogurt, yolk,
        zebra, zoo, zucchini,
        """

    /// categoria inglese | parole italiane (singolare/plurale), separate da virgole
    private static let dati = """
        abacus|abaco/abachi, pallottoliere/pallottolieri
        accordion|fisarmonica/fisarmoniche
        acorn|ghianda/ghiande
        acrobat|acrobata/acrobati, acrobazia/acrobazie
        adult|adulto/adulti, adulta/adulte
        adult_cat|gatto/gatti, gatta/gatte
        agriculture|agricoltura, campagna/campagne, campo coltivato/campi coltivati
        aircraft|velivolo/velivoli, aeromobile/aeromobili
        airplane|aereo/aerei, aeroplano/aeroplani, volo/voli
        airport|aeroporto/aeroporti
        airshow|air show, frecce tricolori, esibizione aerea/esibizioni aeree
        alley|vicolo/vicoli, viuzza/viuzze
        alligator_crocodile|coccodrillo/coccodrilli, alligatore/alligatori
        almond|mandorla/mandorle
        ambulance|ambulanza/ambulanze
        amusement_park|luna park, parco divertimenti/parchi divertimenti, giostre
        anchovy|acciuga/acciughe, alice/alici
        angelfish|pesce angelo/pesci angelo
        animal|animale/animali
        ant|formica/formiche
        antipasti|antipasto/antipasti, stuzzichini, aperitivo/aperitivi, tagliere/taglieri
        anvil|incudine/incudini
        apartment|appartamento/appartamenti, condominio/condomini
        appliance|elettrodomestico/elettrodomestici
        apple|mela/mele
        apricot|albicocca/albicocche
        apron|grembiule/grembiuli
        aquarium|acquario/acquari
        arachnid|aracnide/aracnidi
        arch|arco/archi
        archery|tiro con l'arco
        arena|arena/arene, palazzetto/palazzetti
        armchair|poltrona/poltrone
        art|arte, opera d'arte/opere d'arte
        arthropods|artropode/artropodi
        artichoke|carciofo/carciofi
        arugula|rucola
        asparagus|asparago/asparagi
        athletics|atletica, atletica leggera
        atm|bancomat, sportello automatico/sportelli automatici
        atv|quad
        auditorium|auditorium, sala concerti
        aurora|aurora boreale/aurore boreali, aurora/aurore
        australian_shepherd|pastore australiano/pastori australiani
        automobile|automobile/automobili, auto, macchina/macchine
        avocado|avocado
        axe|ascia/asce, accetta/accette
        baby|neonato/neonati, neonata/neonate, bebè, bambino piccolo/bambini piccoli
        backgammon|backgammon
        backhoe|escavatore/escavatori, ruspa/ruspe
        backpack|zaino/zaini
        bacon|bacon, pancetta
        badminton|badminton, volano/volani
        bag|borsa/borse, sacchetto/sacchetti, busta/buste
        bagel|bagel
        baked_goods|prodotti da forno, dolci da forno, pasticcini, panificati
        baklava|baklava
        balcony|balcone/balconi, terrazzino/terrazzini
        ball|palla/palle, pallone/palloni
        ballet|balletto/balletti, danza classica
        ballet_dancer|ballerina/ballerine, ballerino/ballerini
        ballgames|sport con la palla, partita/partite
        balloon|palloncino/palloncini
        balloon_hotair|mongolfiera/mongolfiere
        banana|banana/banane
        banner|striscione/striscioni, banner
        bar|bar, bancone/banconi, pub
        barbell|bilanciere/bilancieri
        barge|chiatta/chiatte
        barn|fienile/fienili, stalla/stalle
        barnacle|cirripede/cirripedi
        barracuda|barracuda
        barrel|barile/barili, botte/botti
        baseball|baseball
        baseball_bat|mazza da baseball/mazze da baseball
        baseball_hat|cappellino/cappellini, berretto con visiera/berretti con visiera
        basenji|basenji
        basket_container|cesto/cesti, cesta/ceste, cestino/cestini
        basketball|basket, pallacanestro, palla da basket
        basset|basset, basset hound
        bath|vasca/vasche, vasca da bagno/vasche da bagno
        bathrobe|accappatoio/accappatoi
        bathroom|bagno/bagni
        bathroom_faucet|rubinetto/rubinetti
        bathroom_room|bagno/bagni, sala da bagno
        beach|spiaggia/spiagge, mare, lido/lidi
        beagle|beagle
        bean|fagiolo/fagioli
        beanie|berretto di lana/berretti di lana, cuffia/cuffie
        bear|orso/orsi
        bed|letto/letti
        bedding|lenzuola, biancheria da letto, piumone/piumoni
        bedroom|camera da letto/camere da letto, stanza da letto
        bee|ape/api
        beef|manzo, carne di manzo
        beehive|alveare/alveari, arnia/arnie
        beekeeping|apicoltura
        beer|birra/birre
        beet|barbabietola/barbabietole, rapa rossa/rape rosse
        begonia|begonia/begonie
        bell|campana/campane, campanello/campanelli
        bell_pepper|peperone/peperoni
        belltower|campanile/campanili
        bellydance|danza del ventre
        bench|panchina/panchine, panca/panche
        bernese_mountain|bovaro del bernese/bovari del bernese
        berry|bacca/bacche, frutti di bosco
        bib|bavaglino/bavaglini
        bichon|bichon, maltese/maltesi
        bicycle|bicicletta/biciclette, bici
        billboards|cartellone/cartelloni, cartellone pubblicitario/cartelloni pubblicitari
        billiards|biliardo/biliardi
        binoculars|binocolo/binocoli
        bird|uccello/uccelli
        birdhouse|casetta per uccelli/casette per uccelli
        birthday_cake|torta di compleanno/torte di compleanno, compleanno/compleanni
        biryani|biryani
        biscotti|cantucci, cantuccini
        biscuit|biscotto/biscotti
        bison|bisonte/bisonti
        blackberry|mora/more
        bleachers|gradinata/gradinate, tribuna/tribune, spalti
        blender|frullatore/frullatori
        blizzard|bufera di neve/bufere di neve, tormenta/tormente
        blocks|costruzioni, mattoncini, blocchi
        blossom|fioritura/fioriture, fiori di ciliegio, bocciolo/boccioli
        blue_sky|cielo azzurro, cielo sereno, cielo blu
        blueberry|mirtillo/mirtilli
        boar|cinghiale/cinghiali
        board_game|gioco da tavolo/giochi da tavolo
        boat|barca/barche, imbarcazione/imbarcazioni
        boathouse|rimessa per barche
        bobcat|lince rossa/linci rosse
        bodyboard|bodyboard
        bongo_drum|bongo/bonghi
        bonsai|bonsai
        book|libro/libri
        bookshelf|libreria/librerie, scaffale/scaffali
        boot|stivale/stivali, scarpone/scarponi
        bottle|bottiglia/bottiglie
        bouquet|bouquet, mazzo di fiori/mazzi di fiori
        bowl|ciotola/ciotole, scodella/scodelle
        bowling|bowling
        bowtie|papillon, farfallino/farfallini
        boxing|boxe, pugilato
        branch|ramo/rami
        brass_music|ottoni, fiati
        bread|pane/pani
        breakdancing|breakdance, break dance
        brick|mattone/mattoni
        brick_oven|forno a legna/forni a legna
        bride|sposa/spose
        bridesmaid|damigella/damigelle
        bridge|ponte/ponti
        briefcase|valigetta/valigette, ventiquattrore
        broccoli|broccolo/broccoli
        broom|scopa/scope
        brownie|brownie
        bruschetta|bruschetta/bruschette
        bubble_tea|bubble tea
        bucket|secchio/secchi, secchiello/secchielli
        building|edificio/edifici, palazzo/palazzi, costruzione/costruzioni
        bulldog|bulldog
        bulldozer|bulldozer, ruspa/ruspe
        bullfighting|corrida/corride
        bungee|bungee jumping
        burrito|burrito
        bus|autobus, pullman, bus
        butter|burro
        butterfly|farfalla/farfalle
        cabinet|armadietto/armadietti, mobile/mobili, credenza/credenze
        cableway|funivia/funivie, cabinovia/cabinovie
        cactus|cactus
        cage|gabbia/gabbie
        cake|torta/torte, dolce/dolci
        cake_regular|torta/torte
        cakestand|alzatina/alzatine, alzata per dolci
        calculator|calcolatrice/calcolatrici
        calendar|calendario/calendari
        caliper|calibro/calibri
        camel|cammello/cammelli, dromedario/dromedari
        camera|macchina fotografica/macchine fotografiche, fotocamera/fotocamere, reflex
        camping|campeggio/campeggi, camping
        candle|candela/candele
        candlestick|candelabro/candelabri, candeliere/candelieri, portacandele
        candy|caramella/caramelle, dolciumi, caramelle
        candy_cane|bastoncino di zucchero/bastoncini di zucchero
        candy_other|caramella/caramelle, dolciumi
        canine|cane/cani
        canoe|canoa/canoe
        cantaloupe|melone/meloni
        canyon|canyon, gola/gole
        caprese|caprese
        car|auto, macchina/macchine, automobile/automobili
        car_seat|seggiolino auto/seggiolini auto
        caramel|caramello/caramelli, mou
        cardboard_box|scatola di cartone/scatole di cartone, scatolone/scatoloni, pacco/pacchi
        carnation|garofano/garofani
        carnival|carnevale/carnevali
        carousel|giostra/giostre, carosello/caroselli
        carrot|carota/carote
        cart|carrello/carrelli, carretto/carretti
        carton|cartone/cartoni
        cashew|anacardo/anacardi
        casino|casinò
        casserole|sformato/sformati, pirofila/pirofile
        cassette|musicassetta/musicassette, cassetta/cassette
        castle|castello/castelli
        cat|gatto/gatti, gatta/gatte, micio/mici
        caterpillar|bruco/bruchi
        cauliflower|cavolfiore/cavolfiori
        cave|grotta/grotte, caverna/caverne
        cd|cd
        celebration|festa/feste, celebrazione/celebrazioni, festeggiamento/festeggiamenti, party
        celery|sedano/sedani
        celestial_body|corpo celeste/corpi celesti, astro/astri, pianeta/pianeti
        celestial_body_other|stella/stelle, pianeta/pianeti
        cellar|cantina/cantine
        cello|violoncello/violoncelli
        centipede|millepiedi, scolopendra/scolopendre
        cephalopod|polpo/polpi, calamaro/calamari, seppia/seppie, cefalopode/cefalopodi
        cereal|cereali, corn flakes
        ceremony|cerimonia/cerimonie
        cetacean|cetaceo/cetacei
        chainsaw|motosega/motoseghe
        chair|sedia/sedie
        chair_other|sedia/sedie
        chairlift|seggiovia/seggiovie
        chaise|chaise longue, sdraio
        chalkboard|lavagna/lavagne
        chameleon|camaleonte/camaleonti
        chandelier|lampadario/lampadari
        chart|grafico/grafici
        checkbook|libretto degli assegni, assegno/assegni
        cheerleading|cheerleader
        cheese|formaggio/formaggi
        cheesecake|cheesecake
        cheetah|ghepardo/ghepardi
        cherry|ciliegia/ciliegie
        chess|scacchi, scacchiera/scacchiere
        chestnut|castagna/castagne, marrone/marroni
        chewing_gum|gomma da masticare/gomme da masticare, chewing gum
        chihuahua|chihuahua
        child|bambino/bambini, bambina/bambine, bimbo/bimbi, bimba/bimbe, figlio/figli, figlia/figlie
        chimney|comignolo/comignoli, canna fumaria
        chinchilla|cincillà
        chives|erba cipollina
        chocolate|cioccolato, cioccolata/cioccolate, cioccolatino/cioccolatini
        chocolate_chip|gocce di cioccolato
        chopsticks|bacchette
        christmas_decoration|addobbo natalizio/addobbi natalizi, decorazioni di natale, natale
        christmas_tree|albero di natale/alberi di natale, natale
        chrysanthemum|crisantemo/crisantemi
        cigar|sigaro/sigari
        cigarette|sigaretta/sigarette
        cilantro|coriandolo
        circuit_board|scheda elettronica/schede elettroniche, circuito/circuiti
        circus|circo/circhi
        citrus_fruit|agrume/agrumi
        cityscape|città, panorama urbano, skyline
        clam|vongola/vongole
        clarinet|clarinetto/clarinetti
        classroom|aula/aule, classe/classi
        cliff|scogliera/scogliere, rupe/rupi, falesia/falesie
        cloak|mantello/mantelli
        clock|orologio/orologi, sveglia/sveglie
        clock_tower|torre dell'orologio/torri dell'orologio
        closet|armadio/armadi, cabina armadio
        clothesline|stendibiancheria, panni stesi
        clothespin|molletta/mollette
        clothing|vestito/vestiti, abito/abiti, abbigliamento, vestiario
        cloudy|nuvoloso, nuvola/nuvole, nuvoloni
        clover|trifoglio/trifogli, quadrifoglio/quadrifogli
        clown|pagliaccio/pagliacci, clown
        clownfish|pesce pagliaccio/pesci pagliaccio
        cockatoo|cacatua
        cocktail|cocktail, drink
        coconut|cocco, noce di cocco/noci di cocco
        coffee|caffè, espresso, cappuccino/cappuccini
        coffee_bean|chicchi di caffè, caffè in grani
        coin|moneta/monete, monetina/monetine
        coleslaw|insalata di cavolo
        collie|collie
        compass|bussola/bussole
        computer|computer, pc
        computer_keyboard|tastiera/tastiere
        computer_monitor|monitor, schermo/schermi
        computer_mouse|mouse
        computer_tower|case del computer
        concert|concerto/concerti, live, serata/serate, laser
        conch|conchiglia/conchiglie
        condiment|condimento/condimenti, salsa/salse
        conference|conferenza/conferenze, convegno/convegni, riunione/riunioni
        consumer_electronics|elettronica, dispositivo/dispositivi
        container|contenitore/contenitori, barattolo/barattoli
        convertible|cabrio, decappottabile/decappottabili
        conveyance|mezzo di trasporto/mezzi di trasporto, veicolo/veicoli
        cookie|biscotto/biscotti, cookie
        cookware|pentola/pentole, padella/padelle
        coral_reef|barriera corallina, corallo/coralli
        cord|cavo/cavi, filo/fili
        corgi|corgi
        corkscrew|cavatappi
        corn|mais, pannocchia/pannocchie
        cornflower|fiordaliso/fiordalisi
        cosmetic_tool|pennello da trucco/pennelli da trucco, trucco/trucchi, cosmetici
        costume|costume/costumi, travestimento/travestimenti, maschera di carnevale
        cougar|puma
        coupon|buono/buoni, coupon
        cow|mucca/mucche, vacca/vacche, toro/tori
        cowboy_hat|cappello da cowboy/cappelli da cowboy
        coyote_wolf|lupo/lupi, coyote
        crab|granchio/granchi
        cranberry|mirtillo rosso/mirtilli rossi
        crane_construction|gru, cantiere/cantieri
        crate|cassa/casse, cassetta/cassette
        credit_card|carta di credito/carte di credito, bancomat
        creek|ruscello/ruscelli, torrente/torrenti
        crepe|crêpe, crespella/crespelle
        crib|culla/culle, lettino/lettini
        cricket_sport|cricket
        croissant|cornetto/cornetti, croissant, brioche
        crosswalk|strisce pedonali, attraversamento pedonale
        crowd|folla/folle, gente, pubblico
        cruise_ship|nave da crociera/navi da crociera, crociera/crociere
        crutch|stampella/stampelle
        cubicle|open space, postazione di lavoro/postazioni di lavoro
        cucumber|cetriolo/cetrioli
        cup|tazza/tazze, tazzina/tazzine
        cupcake|cupcake
        currency|soldi, denaro, banconota/banconote, valuta
        curry|curry
        curtain|tenda/tende, tendaggio/tendaggi
        cutting_board|tagliere/taglieri
        cycling|ciclismo, pedalata/pedalate, giro in bici
        dachshund|bassotto/bassotti
        daffodil|narciso/narcisi
        dahlia|dalia/dalie
        daikon|daikon
        daisy|margherita/margherite
        dalmatian|dalmata
        dam|diga/dighe
        dancing|ballo/balli, danza/danze, ballare
        dandelion|tarassaco, soffione/soffioni, dente di leone
        dartboard|freccette, bersaglio/bersagli
        dashboard|cruscotto/cruscotti
        daytime|giorno, di giorno, giornata
        decanter|decanter, caraffa/caraffe
        deck|terrazza in legno, deck, ponte della nave
        decoration|decorazione/decorazioni, addobbo/addobbi
        decorative_plant|pianta ornamentale/piante ornamentali, pianta da appartamento/piante da appartamento
        deejay|dj, deejay, disc jockey, consolle, console
        deer|cervo/cervi, daino/daini, capriolo/caprioli
        desert|deserto/deserti
        desk|scrivania/scrivanie
        dessert|dessert, dolce/dolci, dolcetto/dolcetti
        diagram|diagramma/diagrammi, schema/schemi
        dial|quadrante/quadranti
        diaper|pannolino/pannolini
        dice|dado/dadi
        dill|aneto
        dining_room|sala da pranzo/sale da pranzo
        dinosaur|dinosauro/dinosauri
        diorama|diorama/diorami, plastico/plastici
        dirt_road|strada sterrata/strade sterrate, sterrato
        disco_ball|palla stroboscopica, palla da discoteca, sfera specchiata, discoteca/discoteche
        dishwasher|lavastoviglie
        diskette|floppy, dischetto/dischetti
        diving|tuffo/tuffi, immersione/immersioni
        doberman|dobermann, doberman
        dock|molo/moli, banchina/banchine, pontile/pontili
        document|documento/documenti, foglio/fogli, testo/testi
        dog|cane/cani, cagnolino/cagnolini, cucciolo/cuccioli
        doll|bambola/bambole
        dolphin|delfino/delfini
        dome|cupola/cupole
        domicile|casa/case, abitazione/abitazioni
        domino|domino
        donkey|asino/asini, ciuco/ciuchi
        donut|ciambella/ciambelle, donut
        door|porta/porte, portone/portoni
        dove|colomba/colombe
        dragon_parade|danza del drago, drago cinese
        dragonfly|libellula/libellule
        dressage|dressage
        drink|bevanda/bevande, bibita/bibite, drink
        drinking_glass|bicchiere/bicchieri
        driveway|vialetto/vialetti, passo carrabile
        drone_machine|drone/droni
        drum|tamburo/tamburi, batteria/batterie
        dumbbell|manubrio/manubri, pesi
        dumpling|raviolo/ravioli, dumpling
        durian|durian
        eagle|aquila/aquile
        earmuffs|paraorecchie
        easel|cavalletto/cavalletti
        easter_egg|uovo di pasqua/uova di pasqua, pasqua
        edamame|edamame
        egg|uovo/uova
        eggplant|melanzana/melanzane
        electric_fan|ventilatore/ventilatori
        elephant|elefante/elefanti
        elevator|ascensore/ascensori
        elk|alce/alci
        embers|brace/braci
        engine_vehicle|motore/motori
        entertainer|artista di strada/artisti di strada, intrattenitore/intrattenitori, performer
        envelope|busta/buste, lettera/lettere
        equestrian|equitazione
        escalator|scala mobile/scale mobili
        eucalyptus_tree|eucalipto/eucalipti
        evergreen|sempreverde/sempreverdi, abete/abeti, conifera/conifere
        extinguisher|estintore/estintori
        eyeglasses|occhiali
        fairground|fiera/fiere, luna park
        falafel|falafel
        farm|fattoria/fattorie, cascina/cascine
        fedora|borsalino/borsalini, cappello/cappelli
        feline|felino/felini, gatto/gatti
        fence|recinto/recinti, staccionata/staccionate, recinzione/recinzioni, cancello/cancelli
        fencing_sport|scherma
        ferns|felce/felci
        ferret|furetto/furetti
        ferris_wheel|ruota panoramica/ruote panoramiche
        fig|fico/fichi
        figurine|statuina/statuine, figurina/figurine, action figure, soprammobile/soprammobili
        fire|fuoco/fuochi, incendio/incendi, falò
        firecracker|petardo/petardi, botto/botti
        fireplace|caminetto/caminetti, camino/camini
        firetruck|camion dei pompieri, autopompa/autopompe, vigili del fuoco
        fireworks|fuochi d'artificio, fuoco d'artificio
        fish|pesce/pesci
        fishbowl|boccia dei pesci, vaschetta dei pesci
        fishing|pesca
        fishtank|acquario/acquari
        flag|bandiera/bandiere
        flagpole|asta della bandiera/aste delle bandiere
        flame|fiamma/fiamme
        flamingo|fenicottero/fenicotteri
        flan|crème caramel, budino/budini
        flashlight|torcia/torce
        flipchart|lavagna a fogli
        flipper|pinna/pinne
        flower|fiore/fiori
        flower_arrangement|composizione floreale/composizioni floreali, centrotavola
        flute|flauto/flauti
        folding_chair|sedia pieghevole/sedie pieghevoli
        foliage|fogliame, foglie, foliage
        fondue|fonduta/fondute, fondue
        food|cibo/cibi, piatto/piatti, mangiare, pranzo/pranzi, cena/cene
        foosball|calcio balilla, biliardino/biliardini
        football|football americano
        footwear|scarpa/scarpe, calzatura/calzature
        forest|bosco/boschi, foresta/foreste
        fork|forchetta/forchette
        forklift|muletto/muletti, carrello elevatore/carrelli elevatori
        formula_one_car|formula 1, formula uno, monoposto
        fountain|fontana/fontane
        fox|volpe/volpi
        frame|cornice/cornici
        fried_chicken|pollo fritto
        fried_egg|uovo fritto/uova fritte, uovo all'occhio di bue
        fries|patatine, patatine fritte, patate fritte
        frisbee|frisbee
        frog|rana/rane
        frozen|congelato/congelati, gelo
        frozen_dessert|gelato/gelati, semifreddo/semifreddi
        fruit|frutta, frutto/frutti
        fruitcake|panettone/panettoni, torta di frutta
        furniture|mobile/mobili, arredamento, arredo/arredi
        gamepad|joystick, controller, gamepad
        games|gioco/giochi
        garage|garage, box auto
        garden|giardino/giardini, orto/orti
        gargoyle|gargoyle, doccione/doccioni
        garlic|aglio
        gas_mask|maschera antigas/maschere antigas
        gastropod|lumaca/lumache, chiocciola/chiocciole, gasteropode/gasteropodi
        gazebo|gazebo
        gears|ingranaggio/ingranaggi
        gecko|geco/gechi
        gerbil|gerbillo/gerbilli
        german_shepherd|pastore tedesco/pastori tedeschi
        geyser|geyser
        gift|regalo/regali, pacco regalo/pacchi regalo
        gift_card|carta regalo/carte regalo, buono regalo/buoni regalo
        gingerbread|pan di zenzero, omino di pan di zenzero
        giraffe|giraffa/giraffe
        glacier|ghiacciaio/ghiacciai
        glove|guanto/guanti
        glove_other|guanto/guanti
        go_kart|go kart, kart
        goat|capra/capre, caprone/caproni
        goggles|occhialini, maschera da sci/maschere da sci
        goldfish|pesce rosso/pesci rossi
        golf|golf
        golf_ball|pallina da golf/palline da golf
        golf_club|mazza da golf/mazze da golf
        golf_course|campo da golf/campi da golf
        gown|abito da sera/abiti da sera, abito lungo/abiti lunghi
        graduation|laurea/lauree, diploma/diplomi
        graffiti|graffiti, graffito, murales, murale/murali, writing, tag, pezzo/pezzi, bombing, stencil
        grain|grano, cereali, chicchi
        grand_prix|gran premio/gran premi
        grape|uva, acino/acini, grappolo/grappoli
        grapefruit|pompelmo/pompelmi
        grass|erba, prato/prati
        grater|grattugia/grattugie
        grave|tomba/tombe, cimitero/cimiteri, lapide/lapidi
        green_beans|fagiolini
        greenhouse|serra/serre
        greyhound|levriero/levrieri
        grill|griglia/griglie, barbecue, grigliata/grigliate
        grilled_chicken|pollo alla griglia
        groom|sposo/sposi
        guacamole|guacamole
        guava|guava/guave
        guitar|chitarra/chitarre
        gull|gabbiano/gabbiani
        guppy|guppy
        gymnastics|ginnastica
        gyoza|gyoza
        habanero|habanero, peperoncino/peperoncini
        ham|prosciutto/prosciutti
        hamburger|hamburger
        hammer|martello/martelli
        hammock|amaca/amache
        hamster|criceto/criceti
        handwriting|scrittura a mano, appunti, calligrafia
        hangar|hangar
        hangglider|deltaplano/deltaplani
        harbour|porto/porti
        hardhat|casco da cantiere/caschi da cantiere, elmetto/elmetti
        harp|arpa/arpe
        hat|cappello/cappelli
        haze|foschia, nebbia
        headgear|copricapo/copricapi
        headphones|cuffie, auricolari
        health_club|palestra/palestre
        hedgehog|riccio/ricci
        helicopter|elicottero/elicotteri
        helmet|casco/caschi, elmo/elmi
        henna|henné
        herb|erba aromatica/erbe aromatiche, aromi
        heron|airone/aironi
        high_chair|seggiolone/seggioloni
        high_heel|tacco/tacchi, scarpe col tacco
        hiking|escursione/escursioni, trekking, camminata/camminate
        hill|collina/colline
        hippopotamus|ippopotamo/ippopotami
        hockey|hockey
        holly|agrifoglio/agrifogli
        honey|miele
        honeydew|melone bianco/meloni bianchi
        hoodie|felpa/felpe, felpa con cappuccio/felpe con cappuccio
        hookah|narghilè, shisha
        horse|cavallo/cavalli
        horseshoe|ferro di cavallo/ferri di cavallo
        hospital|ospedale/ospedali
        hotdog|hot dog, hotdog
        hound|segugio/segugi
        hourglass|clessidra/clessidre
        house_single|casa/case, villetta/villette, villa/ville
        houseboat|casa galleggiante/case galleggianti
        housewares|casalinghi, utensili da cucina
        hula|hula
        hummingbird|colibrì
        hummus|hummus
        hunting|caccia
        hurdle|ostacolo/ostacoli
        husky|husky
        hydrant|idrante/idranti
        hyena|iena/iene
        ice|ghiaccio/ghiacci
        ice_cream|gelato/gelati, cono gelato/coni gelato
        ice_skates|pattini da ghiaccio
        ice_skating|pattinaggio su ghiaccio
        iceberg|iceberg
        igloo|igloo
        iguana|iguana/iguane
        illustrations|illustrazione/illustrazioni, disegno/disegni, fumetto/fumetti
        insect|insetto/insetti
        interior_room|stanza/stanze, interno/interni, camera/camere
        interior_shop|negozio/negozi
        irish_wolfhound|levriero irlandese/levrieri irlandesi
        iron_clothing|ferro da stiro/ferri da stiro
        island|isola/isole
        ivy|edera/edere
        jack_o_lantern|zucca di halloween/zucche di halloween, halloween
        jack_russell_terrier|jack russell
        jacket|giacca/giacche, giubbotto/giubbotti, giacchetto/giacchetti
        jacuzzi|idromassaggio, jacuzzi, vasca idromassaggio
        jalapeno|jalapeño
        jar|barattolo/barattoli, vasetto/vasetti
        jeans|jeans, denim
        jeep|jeep, fuoristrada
        jello|gelatina/gelatine
        jelly|marmellata/marmellate, confettura/confetture
        jellyfish|medusa/meduse
        jetski|moto d'acqua
        jewelry|gioiello/gioielli, collana/collane, anello/anelli, bracciale/bracciali, orecchino/orecchini
        jigsaw|puzzle
        jockey_horse|fantino/fantini
        joystick|joystick
        jug|brocca/brocche, caraffa/caraffe
        juggling|giocoleria, giocoliere/giocolieri
        juice|succo/succhi, spremuta/spremute
        juicer|spremiagrumi, centrifuga/centrifughe
        jungle|giungla/giungle
        kangaroo|canguro/canguri
        karaoke|karaoke
        kayak|kayak
        kebab|kebab
        keg|fusto/fusti, fusto di birra/fusti di birra
        kettle|bollitore/bollitori
        keypad|tastierino/tastierini
        kickboxing|kickboxing
        kilt|kilt
        kimono|kimono
        kitchen|cucina/cucine
        kitchen_countertop|piano di lavoro/piani di lavoro
        kitchen_faucet|rubinetto/rubinetti
        kitchen_oven|forno/forni
        kitchen_room|cucina/cucine
        kitchen_sink|lavello/lavelli, lavandino/lavandini
        kite|aquilone/aquiloni
        kiteboarding|kitesurf
        kitten|gattino/gattini, micino/micini, gatto/gatti
        kiwi|kiwi
        knife|coltello/coltelli
        koala|koala
        kohlrabi|cavolo rapa/cavoli rapa
        koi|carpa koi/carpe koi
        lab_coat|camice/camici
        ladle|mestolo/mestoli
        ladybug|coccinella/coccinelle
        lake|lago/laghi
        lamp|lampada/lampade, abat-jour
        lamppost|lampione/lampioni
        land|terra, terreno/terreni, paesaggio/paesaggi
        lantern|lanterna/lanterne
        laptop|portatile/portatili, laptop, computer portatile/computer portatili, macbook
        laundry_machine|lavatrice/lavatrici
        lava|lava
        leash|guinzaglio/guinzagli
        leek|porro/porri
        lemon|limone/limoni
        lemongrass|citronella
        lemur|lemure/lemuri
        leopard|leopardo/leopardi
        leotard|body
        lettuce|lattuga/lattughe, insalata/insalate
        library|biblioteca/biblioteche
        license_plate|targa/targhe
        lifejacket|giubbotto salvagente/giubbotti salvagente
        lifesaver|salvagente/salvagenti
        light|luce/luci, illuminazione, laser
        light_bulb|lampadina/lampadine
        lighter|accendino/accendini
        lighthouse|faro/fari
        lightning|fulmine/fulmini, lampo/lampi
        lily|giglio/gigli
        lime|lime
        limousine|limousine
        lion|leone/leoni
        lionfish|pesce scorpione/pesci scorpione
        liquid|liquido/liquidi
        liquor|liquore/liquori, superalcolico/superalcolici, alcol
        living_room|soggiorno/soggiorni, salotto/salotti
        lizard|lucertola/lucertole
        llama|lama, alpaca
        loafer|mocassino/mocassini
        lobster|aragosta/aragoste, astice/astici
        lollipop|lecca lecca
        luggage|valigia/valigie, bagaglio/bagagli
        lychee|litchi
        lynx|lince/linci
        macadamia|macadamia
        machine|macchinario/macchinari
        mackerel|sgombro/sgombri
        magazine|rivista/riviste
        mailbox|cassetta delle lettere/cassette delle lettere, buca delle lettere
        malamute|malamute
        malinois|malinois, pastore belga/pastori belgi
        mallet|mazzuolo/mazzuoli, maglio/magli
        mammal|mammifero/mammiferi
        mandarine|mandarino/mandarini, clementina/clementine
        mango|mango/manghi
        mangosteen|mangostano/mangostani
        mangrove|mangrovia/mangrovie
        manhole|tombino/tombini
        map|mappa/mappe, cartina/cartine
        maple_tree|acero/aceri
        margarita|margarita
        marigold|calendula/calendule
        marshmallow|marshmallow
        marsupial|marsupiale/marsupiali
        martial_arts|arti marziali, karate, judo
        martini|martini
        mask|maschera/maschere, mascherina/mascherine
        mast|albero maestro/alberi maestri
        mastiff|mastino/mastini
        matches|fiammifero/fiammiferi
        material|tessuto/tessuti, materiale/materiali, stoffa/stoffe
        matzo|pane azzimo
        measuring_tape|metro, metro a nastro
        meat|carne/carni
        meatball|polpetta/polpette
        medal|medaglia/medaglie
        media|media
        medicine|medicina/medicine, farmaco/farmaci, pillola/pillole
        megalith|megalite/megaliti, menhir
        megaphone|megafono/megafoni
        melon|melone/meloni
        microphone|microfono/microfoni
        microscope|microscopio/microscopi
        microwave|microonde, forno a microonde
        military_uniform|divisa militare/divise militari, uniforme/uniformi
        milkshake|frappè, milkshake
        millipede|millepiedi
        mistletoe|vischio
        mitten|muffola/muffole, manopola/manopole
        moccasin|mocassino/mocassini
        mojito|mojito
        mollusk|mollusco/molluschi
        money|soldi, denaro, contanti, banconota/banconote
        monitor_lizard|varano/varani
        monorail|monorotaia/monorotaie
        monument|monumento/monumenti
        moon|luna/lune
        moose|alce/alci
        mop|mocio, spazzolone/spazzoloni
        moss|muschio/muschi
        moth|falena/falene
        motocross|motocross
        motorcycle|moto, motocicletta/motociclette, motorino/motorini
        motorhome|camper
        motorsport|motorsport, corsa/corse, gara/gare, autodromo/autodromi
        mountain|montagna/montagne, monte/monti
        mousetrap|trappola per topi
        mower|tosaerba, tagliaerba
        muffin|muffin
        mug|tazza/tazze, tazzone/tazzoni
        museum|museo/musei
        mushroom|fungo/funghi
        music|musica
        musical_instrument|strumento musicale/strumenti musicali, strumento/strumenti
        mussel|cozza/cozze
        mustard|senape
        naan|naan
        nachos|nachos
        nascar|nascar
        necktie|cravatta/cravatte
        nectarine|pesca noce/pesche noci, nettarina/nettarine
        nest|nido/nidi
        newfoundland|terranova
        newspaper|giornale/giornali, quotidiano/quotidiani
        night_sky|cielo notturno, cielo stellato, stelle, notte/notti
        nightclub|discoteca/discoteche, club, locale/locali, serata/serate, disco, party, laser
        nut|noce/noci, frutta secca, nocciola/nocciole
        oak_tree|quercia/querce
        oar|remo/remi
        oatmeal|porridge, fiocchi d'avena
        obelisk|obelisco/obelischi
        ocean|mare/mari, oceano/oceani
        office_supplies|cancelleria, articoli da ufficio
        omelet|frittata/frittate, omelette
        onion|cipolla/cipolle
        optical_equipment|ottica, obiettivo/obiettivi, lente/lenti
        oranges|arancia/arance, arancio/aranci
        orchard|frutteto/frutteti
        orchestra|orchestra/orchestre
        orchid|orchidea/orchidee
        organ_instrument|organo/organi
        origami|origami
        ostrich|struzzo/struzzi
        otter|lontra/lontre
        outdoor|all'aperto, fuori, esterno/esterni, natura
        oven|forno/forni
        owl|gufo/gufi, civetta/civette
        oyster|ostrica/ostriche
        pacifier|ciuccio/ciucci
        paella|paella/paelle
        paintball|paintball
        paintbrush|pennello/pennelli
        painting|quadro/quadri, dipinto/dipinti, pittura/pitture, tela/tele
        palm_tree|palma/palme
        pan|padella/padelle, tegame/tegami
        pancake|pancake
        panda|panda
        papaya|papaya/papaye
        paper_bag|sacchetto di carta/sacchetti di carta
        parachute|paracadute
        parade|parata/parate, sfilata/sfilate, corteo/cortei
        parakeet|parrocchetto/parrocchetti, pappagallino/pappagallini
        parasailing|parasailing
        park|parco/parchi, giardini pubblici
        parking_lot|parcheggio/parcheggi
        parrot|pappagallo/pappagalli
        passionfruit|frutto della passione/frutti della passione, maracuja
        passport|passaporto/passaporti
        pasta|pasta, penne, maccheroni, fusilli
        pastry|pasta/paste, pasticcino/pasticcini, pasticceria
        path|sentiero/sentieri, vialetto/vialetti, percorso/percorsi
        patio|patio, cortile/cortili, terrazza/terrazze
        payphone|cabina telefonica/cabine telefoniche
        pea|pisello/piselli
        peach|pesca/pesche
        peacock|pavone/pavoni
        peanut|arachide/arachidi, nocciolina/noccioline
        pear|pera/pere
        pecan|noce pecan/noci pecan
        pelican|pellicano/pellicani
        pen|penna/penne
        penguin|pinguino/pinguini
        people|persona/persone, gente, amici, gruppo/gruppi
        pepper_veggie|peperone/peperoni
        pepperoni|salame piccante, pepperoni
        peregrine|falco/falchi, falco pellegrino/falchi pellegrini
        performance|spettacolo/spettacoli, esibizione/esibizioni, performance
        pergola|pergolato/pergolati, pergola/pergole
        persimmon|cachi, caco
        petunia|petunia/petunie
        phone|telefono/telefoni, cellulare/cellulari, smartphone, iphone
        piano|pianoforte/pianoforti, piano
        pickle|sottaceto/sottaceti, cetriolino/cetriolini
        pie|crostata/crostate, torta salata/torte salate
        pier|molo/moli, pontile/pontili
        pierogi|pierogi
        pig|maiale/maiali, maialino/maialini
        pigeon|piccione/piccioni
        piggybank|salvadanaio/salvadanai
        pillow|cuscino/cuscini
        pineapple|ananas
        ping_pong|ping pong, tennis tavolo
        pipe|pipa/pipe, tubo/tubi
        pistachio|pistacchio/pistacchi
        pita|pita, piadina/piadine
        pitbull|pitbull
        pizza|pizza/pizze
        plant|pianta/piante
        plate|piatto/piatti
        play_card|carta da gioco/carte da gioco, carte
        playground|parco giochi/parchi giochi
        pliers|pinza/pinze, tenaglia/tenaglie
        plum|prugna/prugne, susina/susine
        podium|podio/podi
        poinsettia|stella di natale/stelle di natale
        poker|poker
        pole|palo/pali
        police_car|auto della polizia, volante/volanti, polizia, carabinieri
        polka_dots|pois
        polo|polo
        pomegranate|melograno/melograni, melagrana/melagrane
        pomeranian|volpino/volpini, pomerania
        poncho|poncho
        poodle|barboncino/barboncini, barbone/barboni
        pool|piscina/piscine
        popcorn|popcorn
        popsicle|ghiacciolo/ghiaccioli
        porch|portico/portici, veranda/verande
        porcupine|porcospino/porcospini, istrice/istrici
        portal|portale/portali, ingresso/ingressi
        porthole|oblò
        pot_cooking|pentola/pentole
        potato|patata/patate
        poultry|pollame, pollo/polli, gallina/galline
        power_saw|sega circolare/seghe circolari, sega elettrica/seghe elettriche
        prairie_dog|cane della prateria/cani della prateria
        pretzel|pretzel, bretzel
        printed_page|pagina stampata/pagine stampate, stampa/stampe, foglio/fogli
        printer|stampante/stampanti
        propeller|elica/eliche
        puck|disco da hockey
        pudding|budino/budini
        puffer_fish|pesce palla/pesci palla
        puffin|pulcinella di mare
        pug|carlino/carlini
        pulley|carrucola/carrucole
        pumpkin|zucca/zucche
        puppet|burattino/burattini, marionetta/marionette, pupazzo/pupazzi
        purse|borsetta/borsette, pochette
        putt|putt
        puzzles|puzzle, rompicapo/rompicapi
        pylon|traliccio/tralicci, pilone/piloni
        pyramid|piramide/piramidi
        pyrotechnics|pirotecnica, effetti pirotecnici, fuochi pirotecnici
        python|pitone/pitoni
        quesadilla|quesadilla
        quinoa|quinoa
        rabbit|coniglio/conigli
        raccoon|procione/procioni
        racquet|racchetta/racchette
        radish|ravanello/ravanelli
        rafting|rafting
        railroad|ferrovia/ferrovie, binario/binari, rotaie
        rainbow|arcobaleno/arcobaleni
        rake|rastrello/rastrelli
        rambutan|rambutan
        ramen|ramen
        rangoli|rangoli
        raptor|rapace/rapaci
        raspberry|lampone/lamponi
        rat|ratto/ratti, topo/topi
        ratchet|cricchetto/cricchetti
        rattlesnake|serpente a sonagli/serpenti a sonagli
        raven|corvo/corvi
        raw_glass|vetro/vetri
        receipt|scontrino/scontrini, ricevuta/ricevute, fattura/fatture
        record|disco/dischi, vinile/vinili, disco in vinile/dischi in vinile, lp, 33 giri, 45 giri
        recreation|svago, tempo libero, divertimento/divertimenti
        red_envelope|busta rossa/buste rosse
        red_wine|vino rosso/vini rossi
        refrigerator|frigorifero/frigoriferi, frigo
        reptile|rettile/rettili
        restaurant|ristorante/ristoranti, trattoria/trattorie, pizzeria/pizzerie
        retriever|retriever, golden retriever, labrador
        rhinoceros|rinoceronte/rinoceronti
        rhubarb|rabarbaro
        rice|riso
        rice_field|risaia/risaie
        rickshaw|risciò
        ridgeback|ridgeback
        rim|cerchione/cerchioni
        rink|pista di pattinaggio/piste di pattinaggio
        risotto|risotto/risotti
        river|fiume/fiumi
        road|strada/strade, via/vie
        road_other|strada/strade
        road_safety_equipment|cono stradale/coni stradali, segnaletica
        rock_climbing|arrampicata/arrampicate, scalata/scalate
        rocket|razzo/razzi
        rocks|roccia/rocce, sasso/sassi, scoglio/scogli, pietra/pietre
        rodent|roditore/roditori
        rodeo|rodeo
        roe|uova di pesce, caviale, bottarga
        rollercoaster|montagne russe
        rollerskates|pattini a rotelle
        rollerskating|pattinaggio a rotelle
        rolling_pin|mattarello/mattarelli
        roof|tetto/tetti
        rope|corda/corde, fune/funi
        rose|rosa/rose
        rosemary|rosmarino
        rotisserie|girarrosto/girarrosti, spiedo/spiedi, rosticceria
        rottweiler|rottweiler
        roulette|roulette
        rowboat|barca a remi/barche a remi
        rugby|rugby
        ruins|rovine, rudere/ruderi, scavi
        sack|sacco/sacchi
        saddle|sella/selle
        safety_vest|gilet catarifrangente/gilet catarifrangenti, gilet ad alta visibilità
        sailboat|barca a vela/barche a vela, veliero/velieri
        saint_bernard|san bernardo
        salad|insalata/insalate
        salami|salame/salami, salumi
        salmon|salmone/salmoni
        samba|samba
        samosa|samosa
        sand|sabbia
        sand_dune|duna/dune
        sandal|sandalo/sandali, ciabatta/ciabatte, infradito
        sandcastle|castello di sabbia/castelli di sabbia
        sandpiper|piovanello/piovanelli
        sandwich|panino/panini, sandwich, tramezzino/tramezzini
        sangria|sangria
        santa_claus|babbo natale
        sardine|sardina/sardine
        sari|sari
        satay|satay
        sauerkraut|crauti
        sausage|salsiccia/salsicce, würstel
        saxophone|sassofono/sassofoni, sax
        scallop|capasanta/capesante
        scarab|scarabeo/scarabei
        scarecrow|spaventapasseri
        scarf|sciarpa/sciarpe, foulard
        schnauzer|schnauzer
        scissors|forbici
        scone|scone
        scooter|scooter, monopattino/monopattini, vespa/vespe
        scoreboard|tabellone/tabelloni, segnapunti
        scorpion|scorpione/scorpioni
        scrambled_eggs|uova strapazzate
        screenshot|screenshot, schermata/schermate
        screwdriver|cacciavite/cacciaviti
        scuba|sub, immersione/immersioni, subacquea
        seabass|branzino/branzini, spigola/spigole
        seafood|frutti di mare, pesce
        seahorse|cavalluccio marino/cavallucci marini
        seal|foca/foche
        sealion|leone marino/leoni marini, otaria/otarie
        seashell|conchiglia/conchiglie
        seasonings|spezie, condimenti
        seat|sedile/sedili, posto a sedere
        seaweed|alga/alghe
        seed|seme/semi
        seesaw|altalena a bilico
        semi_truck|camion, tir, autoarticolato/autoarticolati
        sequoia|sequoia/sequoie
        sesame|sesamo
        setter|setter
        sewing|cucito, cucire
        shark|squalo/squali
        shawarma|shawarma
        shed|capanno/capanni, casetta degli attrezzi
        sheep|pecora/pecore, agnello/agnelli
        sheepdog|cane pastore/cani pastore
        shellfish|crostaceo/crostacei, gambero/gamberi
        shellfish_prepared|gambero/gamberi, crostacei, frutti di mare
        shipyard|cantiere navale/cantieri navali
        shoes|scarpa/scarpe
        shopping_cart|carrello della spesa/carrelli della spesa
        shore|riva/rive, costa/coste, mare, battigia, lungomare
        shower|doccia/docce
        shrub|cespuglio/cespugli, arbusto/arbusti, siepe/siepi
        sidewalk|marciapiede/marciapiedi
        sign|cartello/cartelli, insegna/insegne
        silo|silo/silos
        singer|cantante/cantanti
        skateboard|skateboard, skate
        skateboarding|skateboarding, skate
        skatepark|skatepark
        skating|pattinaggio
        skeleton|scheletro/scheletri
        ski_boot|scarponi da sci
        ski_equipment|sci, attrezzatura da sci
        skiing|sciare, sci, sciata/sciate
        skull|teschio/teschi
        skunk|puzzola/puzzole
        sky|cielo/cieli
        skydiving|paracadutismo, lancio col paracadute
        skyscraper|grattacielo/grattacieli
        sled|slitta/slitte, slittino/slittini
        sledding|giro in slitta
        slide_toy|scivolo/scivoli
        smokestack|ciminiera/ciminiere
        smoking_item|fumo, tabacco
        smoothie|frullato/frullati, smoothie
        snail|lumaca/lumache, chiocciola/chiocciole
        snake|serpente/serpenti, biscia/bisce
        snake_other|serpente/serpenti
        snapdragon|bocca di leone
        snapper|dentice/dentici
        sneaker|sneaker, sneakers, scarpe da ginnastica, scarpa da ginnastica
        snorkeling|snorkeling, maschera e boccaglio
        snow|neve
        snowball|palla di neve/palle di neve
        snowboard|snowboard
        snowboarding|snowboard
        snowman|pupazzo di neve/pupazzi di neve
        snowmobile|motoslitta/motoslitte
        snowshoe|ciaspola/ciaspole, racchette da neve
        soccer|calcio, partita di calcio/partite di calcio
        sock|calzino/calzini, calza/calze
        soda|bibita/bibite, soda, coca cola
        sofa|divano/divani
        softball|softball
        solar_panel|pannello solare/pannelli solari, fotovoltaico
        sombrero|sombrero
        souffle|soufflé
        soup|zuppa/zuppe, minestra/minestre, brodo
        souvlaki|souvlaki, spiedino/spiedini
        spaghetti|spaghetti, pasta
        spaniel|spaniel, cocker
        spareribs|costine, costolette
        sparkler|stellina/stelline
        sparkling_wine|spumante/spumanti, prosecco, champagne
        sparrow|passero/passeri
        spatula|spatola/spatole
        speakers_music|cassa/casse, altoparlante/altoparlanti, casse audio
        speedboat|motoscafo/motoscafi, offshore
        spice|spezia/spezie
        spider|ragno/ragni
        spiderweb|ragnatela/ragnatele
        spinach|spinaci
        spoon|cucchiaio/cucchiai
        sport|sport
        sports_equipment|attrezzatura sportiva, attrezzi sportivi
        sportscar|auto sportiva/auto sportive, supercar, ferrari, lamborghini
        spotlight|riflettore/riflettori, faro/fari, occhio di bue, laser, luci
        springroll|involtino primavera/involtini primavera
        sprinkler|irrigatore/irrigatori
        squash_sport|squash
        squirrel|scoiattolo/scoiattoli
        stadium|stadio/stadi
        stained_glass|vetrata/vetrate
        stairs|scala/scale, scalinata/scalinate, gradini
        starfish|stella marina/stelle marine
        starfruit|carambola/carambole
        statue|statua/statue, scultura/sculture
        steak|bistecca/bistecche, tagliata/tagliate
        steamer_cookware|vaporiera/vaporiere
        stereo|stereo, impianto audio
        stethoscope|stetoscopio/stetoscopi
        sticky_note|post-it, foglietto adesivo/foglietti adesivi
        stingray|razza/razze, pastinaca/pastinache
        stir_fry|saltato in padella, wok
        stool|sgabello/sgabelli
        stopwatch|cronometro/cronometri
        storefront|vetrina/vetrine, negozio/negozi
        stork|cicogna/cicogne
        storm|tempesta/tempeste, temporale/temporali
        stove|fornello/fornelli, piano cottura, stufa/stufe
        straw_drinking|cannuccia/cannucce
        straw_hay|paglia, fieno, balla di fieno/balle di fieno
        strawberry|fragola/fragole
        street|strada/strade, via/vie
        street_sign|cartello stradale/cartelli stradali
        streetcar|tram
        stretcher|barella/barelle
        string_instrument|strumento a corde/strumenti a corde
        stroller|passeggino/passeggini, carrozzina/carrozzine
        structure|struttura/strutture, costruzione/costruzioni
        strudel|strudel
        stuffed_animals|peluche, orsacchiotto/orsacchiotti, pupazzo/pupazzi
        submarine_water|sottomarino/sottomarini
        sugar_cube|zolletta di zucchero/zollette di zucchero
        suit|giacca e cravatta, completo/completi, abito/abiti
        suitcase|valigia/valigie, trolley, bagaglio/bagagli
        sumo|sumo
        sun|sole
        sunbathing|tintarella, prendere il sole, abbronzatura
        sundial|meridiana/meridiane
        sunfish|pesce luna/pesci luna
        sunflower|girasole/girasoli
        sunflower_seeds|semi di girasole
        sunglasses|occhiali da sole
        sunhat|cappello da sole/cappelli da sole, cappello di paglia/cappelli di paglia
        sunset_sunrise|tramonto/tramonti, alba/albe
        surfboard|tavola da surf/tavole da surf
        surfing|surf
        sushi|sushi
        suv|suv
        swan|cigno/cigni
        swimming|nuoto, nuotare
        swimsuit|costume da bagno/costumi da bagno, bikini
        swing_playground|altalena/altalene
        swivel_chair|sedia girevole/sedie girevoli, sedia da ufficio/sedie da ufficio
        sword|spada/spade
        swordfish|pesce spada/pesci spada
        syringe|siringa/siringhe
        tabbouleh|tabulè
        table|tavolo/tavoli, tavola/tavole, tavolino/tavolini
        tableware|stoviglie, tavola apparecchiata
        tachometer|contagiri
        taco|taco/tacos
        taffy|caramella mou/caramelle mou
        tambourine|tamburello/tamburelli
        tapas|tapas
        tapioca_pearls|perle di tapioca
        taro|taro
        tattoo|tatuaggio/tatuaggi, tattoo
        tea_drink|tè, tisana/tisane
        teapot|teiera/teiere
        teen|ragazzo/ragazzi, ragazza/ragazze, adolescente/adolescenti
        telescope|telescopio/telescopi
        television|televisore/televisori, tv, televisione
        tempura|tempura
        tennis|tennis
        tent|tenda/tende, tenda da campeggio/tende da campeggio
        tequila|tequila
        teriyaki|teriyaki
        terrarium|terrario/terrari
        terrier|terrier
        textile|tessuto/tessuti, stoffa/stoffe
        theater|teatro/teatri, palcoscenico/palcoscenici
        thermometer|termometro/termometri
        thermos|thermos, termos
        thermostat|termostato/termostati
        thunderstorm|temporale/temporali
        tiara|tiara/tiare, diadema/diademi, coroncina/coroncine
        ticket|biglietto/biglietti
        tiger|tigre/tigri
        timepiece|orologio/orologi
        tiramisu|tiramisù
        tire|pneumatico/pneumatici, gomma/gomme
        toad|rospo/rospi
        toaster|tostapane
        toaster_oven|fornetto/fornetti
        toilet_seat|water, wc, gabinetto/gabinetti
        tomato|pomodoro/pomodori
        tool|attrezzo/attrezzi, utensile/utensili
        toolbox|cassetta degli attrezzi/cassette degli attrezzi
        tornado|tornado, tromba d'aria/trombe d'aria
        tortilla|tortilla/tortillas
        tortoise|tartaruga/tartarughe, testuggine/testuggini
        toucan|tucano/tucani
        tower|torre/torri
        toy|giocattolo/giocattoli
        track_rail|binario/binari, rotaia/rotaie
        tractor|trattore/trattori
        traffic_light|semaforo/semafori
        trail|sentiero/sentieri, pista/piste
        train|treno/treni
        train_real|treno/treni, locomotiva/locomotive, vagone/vagoni, metropolitana, metro
        train_station|stazione/stazioni, stazione ferroviaria/stazioni ferroviarie
        train_toy|trenino/trenini
        trampoline|trampolino/trampolini, tappeto elastico/tappeti elastici
        tramway|tram, tranvia/tranvie
        trash_can|cestino/cestini, bidone/bidoni, pattumiera/pattumiere, spazzatura
        treadmill|tapis roulant
        tree|albero/alberi
        tricycle|triciclo/tricicli
        tripod|treppiede/treppiedi
        trombone|trombone/tromboni
        trophy|trofeo/trofei, coppa/coppe
        trout|trota/trote
        truck|camion, autocarro/autocarri
        trumpet|tromba/trombe
        tuba|tuba/tube
        tulip|tulipano/tulipani
        tuna|tonno/tonni
        tunnel|tunnel, galleria/gallerie
        turmeric|curcuma
        turntable|giradischi, piatti dj, vinile/vinili, dischi, dj
        turtle|tartaruga/tartarughe
        tuxedo|smoking
        typewriter|macchina da scrivere/macchine da scrivere
        ukulele|ukulele
        umbrella|ombrello/ombrelli, ombrellone/ombrelloni
        underwater|sott'acqua, subacqueo, fondale/fondali
        ungulates|ungulato/ungulati
        urchin|riccio di mare/ricci di mare
        utensil|posata/posate, utensile/utensili
        vacuum|aspirapolvere
        van|furgone/furgoni, van, furgoncino/furgoncini
        vase|vaso/vasi
        vegetable|verdura/verdure, ortaggio/ortaggi
        vegetation|vegetazione, verde
        vehicle|veicolo/veicoli, mezzo/mezzi
        vehicle_toy|macchinina/macchinine, modellino/modellini
        videogame|videogioco/videogiochi, videogame, playstation, console
        vineyard|vigna/vigne, vigneto/vigneti
        violin|violino/violini
        vizsla|vizsla, bracco ungherese
        volcano|vulcano/vulcani
        volleyball|pallavolo, beach volley
        vulture|avvoltoio/avvoltoi
        waffle|waffle, cialda/cialde
        wagon|carro/carri, carretto/carretti
        wakeboarding|wakeboard
        wallet|portafoglio/portafogli
        walrus|tricheco/trichechi
        warship|nave da guerra/navi da guerra
        wasabi|wasabi
        washbasin|lavandino/lavandini, lavabo/lavabi
        watch|orologio da polso/orologi da polso, orologio/orologi, apple watch
        water|acqua
        water_body|specchio d'acqua, acqua, mare, lago/laghi
        watercraft|imbarcazione/imbarcazioni, barca/barche, natante/natanti
        waterfall|cascata/cascate
        watering_can|annaffiatoio/annaffiatoi
        watermelon|anguria/angurie, cocomero/cocomeri
        watermill|mulino ad acqua/mulini ad acqua
        waterpolo|pallanuoto
        watersport|sport acquatici, sport d'acqua
        waterways|canale/canali, corso d'acqua/corsi d'acqua, naviglio/navigli
        wedding|matrimonio/matrimoni, nozze
        wedding_cake|torta nuziale/torte nuziali
        wedding_dress|abito da sposa/abiti da sposa, vestito da sposa/vestiti da sposa
        weight_scale|bilancia/bilance
        weimaraner|weimaraner, bracco di weimar
        wetland|palude/paludi, acquitrino/acquitrini
        wetsuit|muta/mute
        whale|balena/balene
        wheat|grano, frumento, spiga/spighe
        wheel|ruota/ruote
        wheelbarrow|carriola/carriole
        wheelchair|sedia a rotelle/sedie a rotelle
        whisk|frusta/fruste
        white_bread|pane bianco, pancarrè, pan bauletto
        white_wine|vino bianco/vini bianchi
        whiteboard|lavagna bianca/lavagne bianche
        willow|salice/salici
        winch|argano/argani, verricello/verricelli
        wind_turbine|pala eolica/pale eoliche, eolico, turbina eolica/turbine eoliche
        windmill|mulino a vento/mulini a vento
        window|finestra/finestre, vetrata/vetrate
        windsurfing|windsurf
        wine|vino/vini
        wine_bottle|bottiglia di vino/bottiglie di vino
        winter_sport|sport invernali
        wonton|wonton
        wood_natural|legno, legna, tronco/tronchi
        wood_processed|legno lavorato, parquet
        woodpecker|picchio/picchi
        woodwind|strumento a fiato/strumenti a fiato
        workout|allenamento/allenamenti, palestra/palestre, workout
        worm|verme/vermi, lombrico/lombrichi
        wreath|ghirlanda/ghirlande, corona/corone
        wrench|chiave inglese/chiavi inglesi
        wrestling|lotta, wrestling
        xylophone|xilofono/xilofoni
        yacht|yacht, panfilo/panfili
        yarn|lana, gomitolo/gomitoli, filato/filati
        yoga|yoga
        yogurt|yogurt
        yolk|tuorlo/tuorli, rosso d'uovo
        zebra|zebra/zebre
        zoo|zoo
        zucchini|zucchina/zucchine, zucchino/zucchini
        """

    /// sinonimi inglesi per le ricerche del cervello (che scrive in inglese)
    private static let datiInglesi = """
        ocean|sea, seas, seaside
        beach|sea, seaside, beaches
        shore|sea, seaside, coast
        water_body|sea, lake, lakes
        record|vinyl, vinyls, records, lp, lps
        turntable|vinyl, vinyls, turntables, decks
        deejay|dj, djs
        nightclub|club, clubs, disco, party, parties, rave
        celebration|party, parties
        concert|concerts, gig, gigs, laser, lasers
        people|person, friends, group
        child|kid, kids, children
        dog|dogs, puppy, puppies
        cat|cats, kitty, kitties
        graffiti|street art, mural, murals
        sunset_sunrise|sunset, sunsets, sunrise, sunrises
        food|meal, meals, dinner, lunch
        """
}
