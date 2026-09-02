pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "Singletons"

PillSurface {
    id: root

    mTop: 15
    mLeft: 11
    mRight: 11
    mBottom: 14

    property string query: ""
    property int selectedIndex: 0
    property int category: 0
    property var recent: []

    /*
     * Keep the same caret tracking used by Launcher.
     * This is important for the pill's morph/anchor behavior.
     */
    readonly property point caretPoint: {
        void root.width;
        void root.height;
        void search.input.width;

        return search.input.mapToItem(
            root,
            search.input.cursorRectangle.x +
                search.input.cursorRectangle.width / 2,
            search.input.cursorRectangle.y +
                search.input.cursorRectangle.height / 2
        );
    }

    readonly property real caretX: caretPoint.x
    readonly property real caretY: caretPoint.y

    ameForm: "caret"
    amePoint: Qt.point(caretX, caretY)

    /*
     * Six columns.
     *
     * The grid cells themselves expand to fill the available width,
     * rather than adding another column.
     */
    readonly property int columns: 6

    readonly property real cellGap: 4 * root.s

    readonly property real gridCellWidth:
        emojiGrid.width / root.columns

    /*
     * Emoji data:
     *
     * [emoji, searchable name, category]
     *
     * category:
     * 0 = smileys
     * 1 = people
     * 2 = animals
     * 3 = food
     * 4 = travel
     * 5 = activities
     * 6 = objects
     * 7 = symbols
     * 8 = flags
     */
    readonly property var emojiData: [
        ["😀", "grinning face", 0],
        ["😃", "grinning big eyes happy", 0],
        ["😄", "grinning smiling", 0],
        ["😁", "beaming grin", 0],
        ["😆", "laughing squint", 0],
        ["😅", "grinning sweat", 0],
        ["🤣", "rolling floor laughing rofl", 0],
        ["😂", "face tears joy laughing", 0],
        ["🙂", "slightly smiling", 0],
        ["🙃", "upside down", 0],
        ["😉", "wink", 0],
        ["😊", "blush smiling", 0],
        ["😇", "angel halo innocent", 0],
        ["🥰", "love hearts smiling", 0],
        ["😍", "heart eyes love", 0],
        ["🤩", "star eyes excited", 0],
        ["😘", "kiss heart", 0],
        ["😗", "kissing", 0],
        ["😚", "kissing closed eyes", 0],
        ["😋", "yum delicious", 0],
        ["😛", "tongue", 0],
        ["😜", "wink tongue", 0],
        ["🤪", "zany crazy silly", 0],
        ["🤨", "raised eyebrow", 0],
        ["🧐", "monocle", 0],
        ["🤓", "nerd glasses", 0],
        ["😎", "cool sunglasses", 0],
        ["🤯", "mind blown shocked", 0],
        ["🥳", "party celebration", 0],
        ["😏", "smirk", 0],
        ["😒", "unamused", 0],
        ["😞", "disappointed sad", 0],
        ["😔", "sad pensive", 0],
        ["😟", "worried", 0],
        ["😕", "confused", 0],
        ["🙁", "slightly frowning", 0],
        ["☹️", "frowning sad", 0],
        ["😣", "persevering", 0],
        ["😖", "confounded", 0],
        ["😫", "tired", 0],
        ["😩", "weary", 0],
        ["🥺", "pleading puppy eyes", 0],
        ["😢", "cry sad tear", 0],
        ["😭", "loudly crying tears", 0],
        ["😤", "triumph angry", 0],
        ["😠", "angry", 0],
        ["😡", "rage furious", 0],
        ["🤬", "cursing angry", 0],
        ["🤔", "thinking", 0],
        ["🤭", "hand mouth giggle", 0],
        ["🤫", "shush quiet", 0],
        ["🤗", "hugging", 0],
        ["🫡", "salute", 0],
        ["🤐", "zipper mouth", 0],
        ["🤥", "lying pinocchio", 0],
        ["😶", "no mouth", 0],
        ["😐", "neutral", 0],
        ["😑", "expressionless", 0],
        ["😬", "grimacing", 0],
        ["🙄", "rolling eyes", 0],
        ["😯", "hushed surprised", 0],
        ["😮", "open mouth surprised", 0],
        ["😲", "astonished", 0],
        ["🥱", "yawn tired", 0],
        ["😴", "sleep sleeping", 0],
        ["🤤", "drooling", 0],
        ["😪", "sleepy", 0],
        ["😵", "dizzy", 0],
        ["🤠", "cowboy hat", 0],
        ["🥶", "cold freezing", 0],
        ["🥵", "hot sweating", 0],
        ["🤢", "nauseated sick", 0],
        ["🤮", "vomit sick", 0],
        ["🤧", "sneeze sick", 0],
        ["😈", "devil smiling horns", 0],
        ["👿", "angry devil", 0],
        ["💀", "skull dead death", 0],
        ["☠️", "skull crossbones death", 0],
        ["👻", "ghost", 0],
        ["👽", "alien", 0],
        ["🤖", "robot", 0],
        ["💩", "poop", 0],
        ["🤡", "clown", 0],
        ["👹", "ogre", 0],
        ["👺", "goblin", 0],
        ["😺", "cat smile", 0],
        ["😸", "cat grin", 0],
        ["😹", "cat tears joy", 0],
        ["😻", "cat heart eyes", 0],
        ["😼", "cat smirk", 0],
        ["🙀", "cat shocked", 0],
        ["😿", "cat crying", 0],
        ["😾", "cat angry", 0],

        ["👋", "wave hello bye", 1],
        ["🤚", "raised hand", 1],
        ["🖐️", "hand fingers", 1],
        ["✋", "stop hand", 1],
        ["🖖", "vulcan", 1],
        ["👌", "ok", 1],
        ["🤏", "pinch", 1],
        ["✌️", "peace victory", 1],
        ["🤞", "fingers crossed luck", 1],
        ["🤟", "love you", 1],
        ["🤘", "rock horns", 1],
        ["👍", "thumbs up good like", 1],
        ["👎", "thumbs down bad dislike", 1],
        ["👏", "clap applause", 1],
        ["🙌", "raise hands celebration", 1],
        ["👐", "open hands", 1],
        ["🤝", "handshake", 1],
        ["🙏", "pray please thanks", 1],
        ["💪", "muscle strong", 1],
        ["👀", "eyes look see", 1],
        ["👁️", "eye", 1],
        ["🧠", "brain", 1],
        ["👄", "mouth lips", 1],
        ["👅", "tongue", 1],
        ["❤️", "red heart love", 1],
        ["🧡", "orange heart love", 1],
        ["💛", "yellow heart love", 1],
        ["💚", "green heart love", 1],
        ["💙", "blue heart love", 1],
        ["💜", "purple heart love", 1],
        ["🖤", "black heart love", 1],
        ["🤍", "white heart love", 1],
        ["🤎", "brown heart love", 1],
        ["💔", "broken heart", 1],
        ["💕", "two hearts love", 1],
        ["💖", "sparkling heart", 1],
        ["💗", "growing heart", 1],
        ["💘", "heart arrow cupid", 1],
        ["💯", "hundred perfect", 1],

        ["🐶", "dog puppy", 2],
        ["🐱", "cat", 2],
        ["🐭", "mouse", 2],
        ["🐹", "hamster", 2],
        ["🐰", "rabbit bunny", 2],
        ["🦊", "fox", 2],
        ["🐻", "bear", 2],
        ["🐼", "panda", 2],
        ["🐨", "koala", 2],
        ["🐯", "tiger", 2],
        ["🦁", "lion", 2],
        ["🐮", "cow", 2],
        ["🐷", "pig", 2],
        ["🐸", "frog", 2],
        ["🐵", "monkey", 2],
        ["🙈", "see no evil monkey", 2],
        ["🙉", "hear no evil monkey", 2],
        ["🙊", "speak no evil monkey", 2],
        ["🐔", "chicken", 2],
        ["🐧", "penguin", 2],
        ["🐦", "bird", 2],
        ["🦆", "duck", 2],
        ["🦅", "eagle", 2],
        ["🦉", "owl", 2],
        ["🐺", "wolf", 2],
        ["🐗", "boar", 2],
        ["🐴", "horse", 2],
        ["🦄", "unicorn", 2],
        ["🐝", "bee", 2],
        ["🦋", "butterfly", 2],
        ["🐌", "snail", 2],
        ["🐞", "ladybug", 2],
        ["🐜", "ant", 2],
        ["🕷️", "spider", 2],
        ["🐢", "turtle", 2],
        ["🐍", "snake", 2],
        ["🦎", "lizard", 2],
        ["🐙", "octopus", 2],
        ["🦑", "squid", 2],
        ["🐠", "fish", 2],
        ["🐟", "fish", 2],
        ["🐬", "dolphin", 2],
        ["🐳", "whale", 2],
        ["🦈", "shark", 2],
        ["🐊", "crocodile", 2],
        ["🐘", "elephant", 2],
        ["🦒", "giraffe", 2],
        ["🦓", "zebra", 2],
        ["🦍", "gorilla", 2],
        ["🐪", "camel", 2],
        ["🐫", "camel", 2],
        ["🦘", "kangaroo", 2],
        ["🦥", "sloth", 2],
        ["🦦", "otter", 2],
        ["🦔", "hedgehog", 2],

        ["🍎", "apple red fruit", 3],
        ["🍐", "pear fruit", 3],
        ["🍊", "orange fruit", 3],
        ["🍋", "lemon", 3],
        ["🍌", "banana", 3],
        ["🍉", "watermelon", 3],
        ["🍇", "grapes", 3],
        ["🍓", "strawberry", 3],
        ["🫐", "blueberry", 3],
        ["🍒", "cherries", 3],
        ["🍑", "peach", 3],
        ["🥭", "mango", 3],
        ["🍍", "pineapple", 3],
        ["🥝", "kiwi", 3],
        ["🍅", "tomato", 3],
        ["🥑", "avocado", 3],
        ["🍆", "eggplant", 3],
        ["🥕", "carrot", 3],
        ["🌽", "corn", 3],
        ["🌶️", "hot pepper chili", 3],
        ["🍔", "burger hamburger", 3],
        ["🍟", "fries", 3],
        ["🍕", "pizza", 3],
        ["🌭", "hot dog", 3],
        ["🌮", "taco", 3],
        ["🌯", "burrito", 3],
        ["🍿", "popcorn", 3],
        ["🍩", "donut", 3],
        ["🍪", "cookie", 3],
        ["🎂", "birthday cake", 3],
        ["🍰", "cake", 3],
        ["🍫", "chocolate", 3],
        ["🍭", "lollipop candy", 3],
        ["☕", "coffee", 3],
        ["🫖", "tea", 3],
        ["🍵", "tea cup", 3],
        ["🥤", "drink", 3],

        ["🌍", "earth world europe africa", 4],
        ["🌎", "earth world americas", 4],
        ["🌏", "earth world asia", 4],
        ["🌙", "moon night", 4],
        ["☀️", "sun", 4],
        ["⭐", "star", 4],
        ["🌟", "glowing star", 4],
        ["✨", "sparkles", 4],
        ["🔥", "fire hot", 4],
        ["🌈", "rainbow", 4],
        ["☁️", "cloud", 4],
        ["❄️", "snow winter cold", 4],
        ["⚡", "lightning electricity", 4],
        ["🌊", "wave water ocean", 4],
        ["🌸", "cherry blossom flower", 4],
        ["🌹", "rose flower", 4],
        ["🌻", "sunflower", 4],
        ["🌲", "evergreen tree", 4],
        ["🍀", "four leaf clover luck", 4],
        ["🗺️", "map world", 4],
        ["✈️", "airplane flight", 4],
        ["🚗", "car", 4],
        ["🚕", "taxi", 4],
        ["🚌", "bus", 4],
        ["🚆", "train", 4],
        ["🚀", "rocket space", 4],
        ["🏠", "house home", 4],
        ["🏢", "office building", 4],
        ["🏥", "hospital", 4],
        ["🏖️", "beach", 4],

        ["⚽", "soccer football", 5],
        ["🏀", "basketball", 5],
        ["🏈", "football american", 5],
        ["⚾", "baseball", 5],
        ["🎾", "tennis", 5],
        ["🏐", "volleyball", 5],
        ["🎮", "video game controller", 5],
        ["🕹️", "joystick game", 5],
        ["🎲", "dice game", 5],
        ["🎯", "target bullseye", 5],
        ["🎸", "guitar music", 5],
        ["🎹", "piano music", 5],
        ["🎧", "headphones music", 5],
        ["🎤", "microphone music", 5],
        ["🎬", "movie cinema", 5],
        ["🎨", "art palette", 5],
        ["🎉", "party popper celebration", 5],
        ["🎊", "confetti ball celebration", 5],
        ["🏆", "trophy winner", 5],
        ["🥇", "first place medal", 5],
        ["🥈", "second place medal", 5],
        ["🥉", "third place medal", 5],

        ["📱", "phone mobile", 6],
        ["💻", "laptop computer", 6],
        ["🖥️", "desktop computer", 6],
        ["⌨️", "keyboard", 6],
        ["🖱️", "mouse computer", 6],
        ["🖨️", "printer", 6],
        ["💾", "floppy disk save", 6],
        ["💿", "cd", 6],
        ["📷", "camera photo", 6],
        ["🔦", "flashlight", 6],
        ["💡", "light bulb idea", 6],
        ["🔑", "key", 6],
        ["🔒", "locked", 6],
        ["🔓", "unlocked", 6],
        ["🔨", "hammer", 6],
        ["🔧", "wrench", 6],
        ["⚙️", "gear settings", 6],
        ["🛠️", "tools", 6],
        ["📌", "pin", 6],
        ["📎", "paperclip", 6],
        ["✏️", "pencil", 6],
        ["📝", "memo note", 6],
        ["📚", "books", 6],
        ["📖", "book", 6],
        ["✉️", "email mail", 6],
        ["📧", "email", 6],
        ["📁", "folder", 6],
        ["📂", "open folder", 6],
        ["🗑️", "trash delete", 6],

        ["❤️", "heart love", 7],
        ["❣️", "heart exclamation", 7],
        ["💢", "anger", 7],
        ["💥", "collision boom", 7],
        ["💫", "dizzy stars", 7],
        ["💦", "sweat droplets", 7],
        ["💨", "dash wind", 7],
        ["💬", "speech bubble", 7],
        ["💭", "thought bubble", 7],
        ["✔️", "check done", 7],
        ["❌", "cross no", 7],
        ["⭕", "circle", 7],
        ["❗", "exclamation important", 7],
        ["❓", "question", 7],
        ["‼️", "double exclamation", 7],
        ["⁉️", "question exclamation", 7],
        ["⚠️", "warning", 7],
        ["🚫", "prohibited", 7],
        ["🔴", "red circle", 7],
        ["🟠", "orange circle", 7],
        ["🟡", "yellow circle", 7],
        ["🟢", "green circle", 7],
        ["🔵", "blue circle", 7],
        ["🟣", "purple circle", 7],
        ["⚫", "black circle", 7],
        ["⚪", "white circle", 7],
        ["⬆️", "up arrow", 7],
        ["⬇️", "down arrow", 7],
        ["⬅️", "left arrow", 7],
        ["➡️", "right arrow", 7],
        ["🔄", "refresh rotate", 7],
        ["♻️", "recycle", 7],
        ["☑️", "checked box", 7],
        ["☑", "check box", 7],

        ["🇮🇳", "india", 8],
        ["🇺🇸", "usa america united states", 8],
        ["🇬🇧", "uk britain england", 8],
        ["🇯🇵", "japan", 8],
        ["🇨🇳", "china", 8],
        ["🇰🇷", "korea", 8],
        ["🇩🇪", "germany", 8],
        ["🇫🇷", "france", 8],
        ["🇮🇹", "italy", 8],
        ["🇪🇸", "spain", 8],
        ["🇨🇦", "canada", 8],
        ["🇦🇺", "australia", 8],
        ["🇧🇷", "brazil", 8],
        ["🇷🇺", "russia", 8],
        ["🇺🇦", "ukraine", 8]

        ["🥲", "smiling face tear bittersweet", 0],
        ["🥹", "holding back tears emotional touched", 0],
        ["🫠", "melting face melt hot embarrassed", 0],
        ["🫢", "open eyes hand over mouth shocked", 0],
        ["🫣", "peeking face shy embarrassed", 0],
        ["🫥", "dotted line face invisible hidden", 0],
        ["🫤", "diagonal mouth unsure", 0],
        ["🫨", "shaking face shock", 0],
        ["🫩", "face bags under eyes tired exhausted", 0],
        ["😮‍💨", "face exhaling sigh relief tired", 0],
        ["😵‍💫", "spiral eyes dizzy confused", 0],
        ["🥸", "disguised face disguise glasses", 0],
        ["🥴", "woozy face dizzy", 0],
        ["🤒", "thermometer face sick fever", 0],
        ["🤕", "bandage face injured hurt", 0],
        ["🙂‍↔️", "head shaking no horizontal", 0],
        ["🙂‍↕️", "head shaking yes vertical", 0],
        ["😶‍🌫️", "face clouds fog smoke", 0],
        ["❤️‍🔥", "heart on fire love passion", 0],
        ["❤️‍🩹", "mending heart healing recovery", 0],
        ["🫵", "pointing at viewer you", 1],
        ["🫱", "rightwards hand", 1],
        ["🫲", "leftwards hand", 1],
        ["🫳", "palm down hand", 1],
        ["🫴", "palm up hand", 1],
        ["🫷", "leftwards pushing hand stop", 1],
        ["🫸", "rightwards pushing hand stop", 1],
        ["🫰", "finger heart hand love", 1],
        ["🫶", "heart hands love", 1],
        ["🫦", "biting lip", 1],
        ["🫀", "anatomical heart", 1],
        ["🫁", "lungs", 1],
        ["🦾", "mechanical arm robotic", 1],
        ["🦿", "mechanical leg robotic", 1],
        ["🦻", "ear hearing aid", 1],
        ["🫂", "people hugging hug", 1],
        ["🧎", "kneeling person", 1],
        ["🧍", "standing person", 1],
        ["🧑‍🍼", "person feeding baby", 1],
        ["🧑‍🎓", "student graduate", 1],
        ["🧑‍🏫", "teacher", 1],
        ["🧑‍⚕️", "health worker doctor", 1],
        ["🧑‍⚖️", "judge", 1],
        ["🧑‍🌾", "farmer", 1],
        ["🧑‍🍳", "cook chef", 1],
        ["🧑‍🔧", "mechanic", 1],
        ["🧑‍🏭", "factory worker", 1],
        ["🧑‍💻", "technologist programmer", 1],
        ["🧑‍🎤", "singer", 1],
        ["🧑‍🎨", "artist", 1],
        ["🧑‍🚀", "astronaut", 1],
        ["🧑‍🚒", "firefighter", 1],
        ["🗣️", "speaking head talking", 1],
        ["👤", "bust silhouette person", 1],
        ["👥", "busts silhouettes people", 1],
        ["🥷", "ninja", 1],
        ["🧕", "headscarf hijab", 1],
        ["🫅", "person crown royalty", 1],
        ["🧑‍🦯", "person white cane blind", 1],
        ["🧑‍🦼", "person wheelchair motorized", 1],
        ["🧑‍🦽", "person wheelchair manual", 1],
        ["🤹", "juggling", 1],
        ["🤽", "water polo", 1],
        ["🤾", "handball", 1],
        ["🏄", "surfing", 1],
        ["🚣", "rowing boat", 1],
        ["🧗", "climbing", 1],
        ["🏋️", "weight lifting gym", 1],
        ["🤸", "cartwheel gymnastics", 1],
        ["⛹️", "bouncing ball basketball", 1],
        ["🏌️", "golf", 1],
        ["🏇", "horse racing", 1],
        ["🤺", "fencing", 1],
        ["🫎", "moose", 2],
        ["🫏", "donkey", 2],
        ["🪽", "wing", 2],
        ["🪿", "goose", 2],
        ["🪼", "jellyfish", 2],
        ["🪸", "coral", 2],
        ["🪻", "hyacinth flower", 2],
        ["🪷", "lotus flower", 2],
        ["🪹", "empty nest", 2],
        ["🪺", "nest eggs", 2],
        ["🪲", "beetle bug", 2],
        ["🪳", "cockroach bug", 2],
        ["🪰", "fly insect", 2],
        ["🪱", "worm", 2],
        ["🪴", "potted plant", 2],
        ["🪵", "wood log", 2],
        ["🪨", "rock stone", 2],
        ["🦤", "dodo", 2],
        ["🦭", "seal", 2],
        ["🦬", "bison buffalo", 2],
        ["🦣", "mammoth", 2],
        ["🦫", "beaver", 2],
        ["🦧", "orangutan", 2],
        ["🦨", "skunk", 2],
        ["🦩", "flamingo", 2],
        ["🦮", "guide dog", 2],
        ["🐕‍🦺", "service dog", 2],
        ["🐈‍⬛", "black cat", 2],
        ["🐻‍❄️", "polar bear", 2],
        ["🦏", "rhinoceros rhino", 2],
        ["🦛", "hippopotamus hippo", 2],
        ["🦙", "llama", 2],
        ["🦝", "raccoon", 2],
        ["🦡", "badger", 2],
        ["🦢", "swan", 2],
        ["🦚", "peacock", 2],
        ["🦜", "parrot", 2],
        ["🦇", "bat", 2],
        ["🦂", "scorpion", 2],
        ["🦟", "mosquito", 2],
        ["🦗", "cricket insect", 2],
        ["🕸️", "spider web", 2],
        ["🪶", "feather", 2],
        ["🌱", "seedling plant", 2],
        ["🌵", "cactus", 2],
        ["🎋", "tanabata tree", 2],
        ["🍂", "fallen leaves autumn", 2],
        ["🍁", "maple leaf autumn", 2],
        ["🍃", "leaf wind", 2],
        ["🌾", "rice plant", 2],
        ["🌿", "herb", 2],
        ["☘️", "shamrock", 2],
        ["🌴", "palm tree", 2],
        ["🫒", "olive", 3],
        ["🫛", "pea peas", 3],
        ["🫚", "ginger", 3],
        ["🫜", "root vegetable", 3],
        ["🧄", "garlic", 3],
        ["🧅", "onion", 3],
        ["🫑", "bell pepper", 3],
        ["🥦", "broccoli", 3],
        ["🥬", "leafy green lettuce", 3],
        ["🥒", "cucumber", 3],
        ["🥔", "potato", 3],
        ["🍠", "sweet potato", 3],
        ["🥐", "croissant", 3],
        ["🥯", "bagel", 3],
        ["🥖", "baguette bread", 3],
        ["🧇", "waffle", 3],
        ["🥞", "pancakes", 3],
        ["🧈", "butter", 3],
        ["🧂", "salt", 3],
        ["🥨", "pretzel", 3],
        ["🧀", "cheese", 3],
        ["🥩", "steak meat", 3],
        ["🥓", "bacon", 3],
        ["🥚", "egg", 3],
        ["🍳", "fried egg cooking", 3],
        ["🍣", "sushi", 3],
        ["🍱", "bento box", 3],
        ["🍙", "rice ball", 3],
        ["🍘", "rice cracker", 3],
        ["🍥", "fish cake", 3],
        ["🥟", "dumpling", 3],
        ["🥠", "fortune cookie", 3],
        ["🥡", "takeout box", 3],
        ["🍜", "ramen noodles", 3],
        ["🍝", "spaghetti pasta", 3],
        ["🍛", "curry rice", 3],
        ["🍲", "pot stew soup", 3],
        ["🫕", "fondue", 3],
        ["🥣", "bowl spoon cereal", 3],
        ["🥗", "green salad", 3],
        ["🍦", "ice cream", 3],
        ["🍧", "shaved ice", 3],
        ["🍨", "ice cream bowl", 3],
        ["🍮", "custard pudding", 3],
        ["🍯", "honey pot", 3],
        ["🧋", "bubble tea boba", 3],
        ["🥛", "milk", 3],
        ["🍼", "baby bottle", 3],
        ["🫗", "pouring liquid", 3],
        ["🧃", "juice box", 3],
        ["🧊", "ice cube", 3],
        ["🗿", "moai statue", 4],
        ["🗽", "statue liberty", 4],
        ["🗼", "tokyo tower", 4],
        ["🏰", "castle", 4],
        ["🏯", "japanese castle", 4],
        ["🏟️", "stadium", 4],
        ["🎡", "ferris wheel", 4],
        ["🎢", "roller coaster", 4],
        ["🎠", "carousel", 4],
        ["⛲", "fountain", 4],
        ["⛱️", "beach umbrella", 4],
        ["🏝️", "desert island", 4],
        ["🏜️", "desert", 4],
        ["🏕️", "camping", 4],
        ["⛺", "tent camping", 4],
        ["🛖", "hut", 4],
        ["🛣️", "motorway highway road", 4],
        ["🛤️", "railway track", 4],
        ["🗻", "mount fuji mountain", 4],
        ["🏔️", "snow mountain", 4],
        ["🌋", "volcano", 4],
        ["🌌", "milky way galaxy", 4],
        ["🌠", "shooting star", 4],
        ["🌅", "sunrise", 4],
        ["🌄", "mountain sunrise", 4],
        ["🌇", "sunset city", 4],
        ["🌆", "city sunset", 4],
        ["🚲", "bicycle bike", 4],
        ["🛴", "scooter", 4],
        ["🛵", "motor scooter", 4],
        ["🏍️", "motorcycle", 4],
        ["🚙", "suv", 4],
        ["🛻", "pickup truck", 4],
        ["🚐", "minivan", 4],
        ["🚑", "ambulance", 4],
        ["🚒", "fire engine truck", 4],
        ["🚓", "police car", 4],
        ["🚔", "police car", 4],
        ["🚚", "delivery truck", 4],
        ["🚛", "articulated truck", 4],
        ["🚜", "tractor", 4],
        ["🚁", "helicopter", 4],
        ["🛩️", "small airplane", 4],
        ["🛫", "airplane departure", 4],
        ["🛬", "airplane arrival", 4],
        ["🚢", "ship", 4],
        ["⛴️", "ferry", 4],
        ["🚤", "speedboat", 4],
        ["🛥️", "motor boat", 4],
        ["🧭", "compass", 4],
        ["🧳", "luggage suitcase", 4],
        ["🛂", "passport control", 4],
        ["🛃", "customs", 4],
        ["🛄", "baggage claim", 4],
        ["🛅", "left luggage", 4],
        ["🪁", "kite flying", 5],
        ["🪀", "yo yo toy", 5],
        ["🛝", "playground slide", 5],
        ["🛹", "skateboard", 5],
        ["🛼", "roller skate", 5],
        ["🎣", "fishing", 5],
        ["🤿", "diving snorkeling", 5],
        ["🎽", "running shirt", 5],
        ["🎿", "skiing", 5],
        ["⛷️", "skier", 5],
        ["🏂", "snowboarder", 5],
        ["🪂", "parachute", 5],
        ["🎳", "bowling", 5],
        ["🎱", "pool billiards", 5],
        ["🪄", "magic wand", 5],
        ["🎭", "performing arts theater", 5],
        ["🎪", "circus tent", 5],
        ["🎟️", "admission ticket", 5],
        ["🎫", "ticket", 5],
        ["🎼", "musical score", 5],
        ["🎵", "music note", 5],
        ["🎶", "music notes", 5],
        ["🎷", "saxophone", 5],
        ["🎺", "trumpet", 5],
        ["🎻", "violin", 5],
        ["🥁", "drum", 5],
        ["🪕", "banjo", 5],
        ["🪇", "maracas", 5],
        ["🪈", "flute", 5],
        ["🎙️", "studio microphone", 5],
        ["🎚️", "level slider music", 5],
        ["🎛️", "control knobs", 5],
        ["🧩", "puzzle piece", 5],
        ["♟️", "chess pawn", 5],
        ["🃏", "joker card", 5],
        ["🀄", "mahjong", 5],
        ["🎴", "playing cards", 5],
        ["🪆", "nesting dolls", 5],
        ["🎁", "gift present", 5],
        ["🎈", "balloon", 5],
        ["🎄", "christmas tree", 5],
        ["🎆", "fireworks", 5],
        ["🎇", "sparkler fireworks", 5],
        ["🧨", "firecracker", 5],
        ["🪅", "pinata", 5],
        ["🪩", "disco ball", 5],
        ["🪪", "identification card id", 6],
        ["🫧", "bubbles", 6],
        ["🪫", "low battery", 6],
        ["🛜", "wireless wifi internet", 6],
        ["🪜", "ladder", 6],
        ["🛗", "elevator lift", 6],
        ["🪞", "mirror", 6],
        ["🪟", "window", 6],
        ["🪑", "chair", 6],
        ["🛋️", "couch sofa", 6],
        ["🪧", "placard sign", 6],
        ["🪏", "shovel", 6],
        ["🪚", "carpentry saw", 6],
        ["🪛", "screwdriver", 6],
        ["🪝", "hook", 6],
        ["🪓", "axe", 6],
        ["🪣", "bucket", 6],
        ["🧲", "magnet", 6],
        ["🪤", "mouse trap", 6],
        ["🧰", "toolbox", 6],
        ["🧯", "fire extinguisher", 6],
        ["🪥", "toothbrush", 6],
        ["🧴", "lotion bottle", 6],
        ["🧷", "safety pin", 6],
        ["🧹", "broom", 6],
        ["🧺", "basket", 6],
        ["🧻", "toilet paper", 6],
        ["🧼", "soap", 6],
        ["🪒", "razor", 6],
        ["🧽", "sponge", 6],
        ["🧸", "teddy bear", 6],
        ["🧮", "abacus", 6],
        ["📡", "satellite antenna", 6],
        ["🛰️", "satellite", 6],
        ["🛸", "flying saucer ufo", 6],
        ["🔭", "telescope", 6],
        ["🔬", "microscope", 6],
        ["🧪", "test tube chemistry", 6],
        ["🧫", "petri dish", 6],
        ["🧬", "dna", 6],
        ["🩻", "x ray", 6],
        ["🩹", "bandage", 6],
        ["🩺", "stethoscope", 6],
        ["🩸", "drop blood", 6],
        ["🪮", "hair pick comb", 6],
        ["🪭", "folding hand fan", 6],
        ["🪔", "diya lamp", 6],
        ["🕯️", "candle", 6],
        ["🏮", "red paper lantern", 6],
        ["🪦", "headstone grave", 6],
        ["🛒", "shopping cart", 6],
        ["🧿", "nazar evil eye blue eye protection", 7],
        ["🪬", "hamsa hand protection amulet", 7],
        ["🩷", "pink heart love", 7],
        ["🩵", "light blue heart love", 7],
        ["🩶", "grey heart love", 7],
        ["💟", "heart decoration", 7],
        ["💌", "love letter", 7],
        ["💝", "heart ribbon", 7],
        ["💞", "revolving hearts", 7],
        ["💓", "beating heart", 7],
        ["☮️", "peace symbol", 7],
        ["✝️", "latin cross", 7],
        ["☪️", "star crescent islam", 7],
        ["🕉️", "om hindu", 7],
        ["☸️", "wheel dharma buddhism", 7],
        ["✡️", "star david jewish", 7],
        ["🔯", "dotted six pointed star", 7],
        ["🕎", "menorah", 7],
        ["☯️", "yin yang", 7],
        ["☦️", "orthodox cross", 7],
        ["🛐", "place worship", 7],
        ["♈", "aries zodiac", 7],
        ["♉", "taurus zodiac", 7],
        ["♊", "gemini zodiac", 7],
        ["♋", "cancer zodiac", 7],
        ["♌", "leo zodiac", 7],
        ["♍", "virgo zodiac", 7],
        ["♎", "libra zodiac", 7],
        ["♏", "scorpio zodiac", 7],
        ["♐", "sagittarius zodiac", 7],
        ["♑", "capricorn zodiac", 7],
        ["♒", "aquarius zodiac", 7],
        ["♓", "pisces zodiac", 7],
        ["⛎", "ophiuchus zodiac", 7],
        ["🔱", "trident emblem", 7],
        ["⚜️", "fleur de lis", 7],
        ["⚕️", "medical symbol", 7],
        ["⚛️", "atom symbol", 7],
        ["☢️", "radioactive", 7],
        ["☣️", "biohazard", 7],
        ["🚸", "children crossing", 7],
        ["🔞", "eighteen no underage", 7],
        ["〰️", "wavy dash", 7],
        ["➰", "curly loop", 7],
        ["➿", "double curly loop", 7],
        ["〽️", "part alternation mark", 7],
        ["🔆", "bright button", 7],
        ["🔅", "dim button", 7],
        ["🔳", "black square button", 7],
        ["🔲", "white square button", 7],
        ["▪️", "black small square", 7],
        ["▫️", "white small square", 7],
        ["◾", "black medium small square", 7],
        ["◽", "white medium small square", 7],
        ["◼️", "black medium square", 7],
        ["◻️", "white medium square", 7],
        ["⬛", "black large square", 7],
        ["⬜", "white large square", 7],
        ["🔺", "red triangle up", 7],
        ["🔻", "red triangle down", 7],
        ["🔶", "orange diamond", 7],
        ["🔷", "blue diamond", 7],
        ["🔸", "orange small diamond", 7],
        ["🔹", "blue small diamond", 7],
        ["♾️", "infinity", 7],
        ["🔀", "shuffle tracks", 7],
        ["🔁", "repeat", 7],
        ["🔂", "repeat single", 7],
        ["⏩", "fast forward", 7],
        ["⏪", "fast reverse", 7],
        ["⏫", "fast up", 7],
        ["⏬", "fast down", 7],
        ["🔼", "up button", 7],
        ["🔽", "down button", 7],
        ["⏸️", "pause button", 7],
        ["⏹️", "stop button", 7],
        ["⏺️", "record button", 7],
        ["⏭️", "next track", 7],
        ["⏮️", "previous track", 7],
        ["🔘", "radio button", 7],
        ["🆕", "new button", 7],
        ["🆗", "ok button", 7],
        ["🆙", "up button", 7],
        ["🆒", "cool button", 7],
        ["🆓", "free button", 7],
        ["🆖", "ng button", 7],
        ["🆘", "sos button", 7],
        ["🆚", "vs button", 7],
        ["🈶", "japanese have button", 7],
        ["🈚", "japanese free button", 7],
        ["🈯", "japanese reserved button", 7],
        ["🈲", "japanese prohibited button", 7],
        ["🈳", "japanese vacancy button", 7],
        ["🈴", "japanese passing grade", 7],
        ["🈵", "japanese full button", 7],
        ["🈹", "japanese discount button", 7],
        ["🈺", "japanese open for business", 7],
        ["🈷️", "japanese monthly amount", 7],
        ["🈸", "japanese application button", 7],
        ["🉐", "japanese bargain", 7],
        ["🉑", "japanese acceptable", 7],
        ["🇦🇷", "argentina flag", 8],
        ["🇦🇹", "austria flag", 8],
        ["🇧🇪", "belgium flag", 8],
        ["🇨🇭", "switzerland flag", 8],
        ["🇨🇱", "chile flag", 8],
        ["🇨🇴", "colombia flag", 8],
        ["🇨🇿", "czech republic flag", 8],
        ["🇩🇰", "denmark flag", 8],
        ["🇫🇮", "finland flag", 8],
        ["🇬🇷", "greece flag", 8],
        ["🇭🇰", "hong kong flag", 8],
        ["🇭🇺", "hungary flag", 8],
        ["🇮🇪", "ireland flag", 8],
        ["🇮🇩", "indonesia flag", 8],
        ["🇮🇱", "israel flag", 8],
        ["🇮🇷", "iran flag", 8],
        ["🇲🇾", "malaysia flag", 8],
        ["🇲🇽", "mexico flag", 8],
        ["🇳🇱", "netherlands holland flag", 8],
        ["🇳🇴", "norway flag", 8],
        ["🇳🇿", "new zealand flag", 8],
        ["🇵🇭", "philippines flag", 8],
        ["🇵🇱", "poland flag", 8],
        ["🇵🇹", "portugal flag", 8],
        ["🇸🇪", "sweden flag", 8],
        ["🇸🇬", "singapore flag", 8],
        ["🇹🇭", "thailand flag", 8],
        ["🇹🇷", "turkey flag", 8],
        ["🇹🇼", "taiwan flag", 8],
        ["🇻🇳", "vietnam flag", 8],
        ["🇿🇦", "south africa flag", 8],
        ["🇪🇺", "european union eu flag", 8],
        ["🏴", "black flag", 8],
        ["🏳️", "white flag", 8],
        ["🏁", "checkered racing flag", 8],
        ["🚩", "triangular flag", 8],
        ["🏳️‍🌈", "rainbow pride flag", 8],
        ["🏳️‍⚧️", "transgender pride flag", 8],
    ]

    readonly property var categoryIcons: [
        "⌛",
        "😀",
        "👋",
        "🐶",
        "🍎",
        "🌍",
        "🎮",
        "💻",
        "❤️",
        "🇮🇳"
    ]

    function matches(entry, text) {
        if (!text || text.trim().length === 0)
            return true;

        var words = text.toLowerCase().trim().split(/\s+/);
        var haystack =
            String(entry[0] + " " + entry[1]).toLowerCase();

        for (var i = 0; i < words.length; ++i) {
            if (haystack.indexOf(words[i]) === -1)
                return false;
        }

        return true;
    }

    readonly property var filtered: {
        var out = [];
        var q = root.query.trim();

        /*
         * Search always wins over category filtering.
         * An emoji has to satisfy both when a category is selected.
         */
        for (var i = 0; i < root.emojiData.length; ++i) {
            var e = root.emojiData[i];

            if (root.category !== 0 &&
                e[2] !== root.category - 1)
                continue;

            if (!root.matches(e, q))
                continue;

            out.push(e);
        }

        return out;
    }

    function focusField() {
        search.input.forceActiveFocus();
    }

    function move(delta) {
        if (root.filtered.length === 0)
            return;

        root.selectedIndex = Math.max(
            0,
            Math.min(
                root.filtered.length - 1,
                root.selectedIndex + delta
            )
        );

        emojiGrid.positionViewAtIndex(
            root.selectedIndex,
            GridView.Contain
        );
    }

    function addRecent(value) {
        var next = [value];

        for (var i = 0; i < root.recent.length; ++i) {
            if (root.recent[i] !== value)
                next.push(root.recent[i]);
        }

        root.recent = next.slice(0, 24);
    }

    /*
     * Copy AND type.
     */
    function copyEmoji(value) {
        root.addRecent(value);
        root.requestClose();

        Quickshell.execDetached([
            "sh",
            "-c",
            "printf '%s' \"$1\" | wl-copy; sleep 0.10; wtype -- \"$1\"",
            "_",
            value
        ]);
    }

    onQueryChanged: {
        root.selectedIndex = 0;
    }

    onCategoryChanged: {
        root.selectedIndex = 0;
    }

    /*
     * Same focus lifecycle as Launcher.
     */
    onActiveChanged: {
        if (active) {
            query = "";
            search.text = "";
            category = 0;
            selectedIndex = 0;

            Qt.callLater(root.focusField);
        }
    }

    /*
     * Search
     *
     * Deliberately using SearchField exactly like Launcher.
     * No custom TextField and no custom cursor.
     */
    SearchField {
        id: search

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right

        s: root.s
        kanji: "絵"
        placeholder: "Search emojis"
        counterText: ""

        onTextChanged: {
            root.query = text;
            root.selectedIndex = 0;
        }

        onMoved: (d) => root.move(d)

        onAccepted: {
            if (root.filtered.length > 0) {
                root.copyEmoji(
                    root.filtered[root.selectedIndex][0]
                );
            }
        }

        onDismissed: root.requestClose()
    }

    /*
     * Same divider structure as Launcher.
     * Invisible because the visible line is already supplied by the
     * search component/layout.
     */
    Rectangle {
        id: divider

        anchors.top: search.bottom
        anchors.topMargin: 2 * root.s
        anchors.left: parent.left
        anchors.right: parent.right

        height: 1
        color: Theme.hair
        opacity: 0
    }

    /*
     * Category filter row.
     *
     * It is constrained to the actual available width, so all
     * ten buttons remain inside the 360px pill.
     */
    Item {
        id: categoryRow

        anchors.top: divider.bottom
        anchors.topMargin: 5 * root.s
        anchors.left: parent.left
        anchors.right: parent.right

        height: 34 * root.s

        Row {
            anchors.fill: parent
            spacing: 3 * root.s

            Repeater {
                model: root.categoryIcons.length

                delegate: Rectangle {
                    required property int index

                    width: (
                        categoryRow.width -
                        (root.categoryIcons.length - 1) *
                            3 * root.s
                    ) / root.categoryIcons.length

                    height: categoryRow.height

                    radius: 9 * root.s

                    color: root.category === index
                        ? Theme.frameBg
                        : Qt.rgba(
                            0.94,
                            0.88,
                            0.84,
                            0.025
                        )

                    border.width:
                        root.category === index ? 1 : 0

                    border.color: Theme.frameBorder

                    Text {
                        anchors.centerIn: parent

                        text: root.categoryIcons[index]

                        font.family: "Noto Color Emoji"
                        font.pixelSize: 17 * root.s

                        renderType: Text.NativeRendering
                    }

                    MouseArea {
                        anchors.fill: parent

                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            root.category = index;
                            root.selectedIndex = 0;
                        }
                    }
                }
            }
        }
    }

    /*
     * Emoji grid.
     *
     * Six columns are fixed. Each column receives an equal share
     * of the available width, making the cells substantially larger
     * than the previous 48px cells.
     */
    GridView {
        id: emojiGrid

        anchors.top: categoryRow.bottom
        anchors.topMargin: 5 * root.s

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        clip: true

        boundsBehavior: Flickable.StopAtBounds

        cellWidth: emojiGrid.width / root.columns
        cellHeight: 49 * root.s

        model: root.filtered.length

        delegate: Item {
            id: emojiCell

            required property int index

            width: emojiGrid.cellWidth
            height: emojiGrid.cellHeight

            readonly property bool selected:
                index === root.selectedIndex

            Rectangle {
                anchors.centerIn: parent

                /*
                 * Larger buttons, but with a small margin so they
                 * don't touch each other or the pill border.
                 */
                width: Math.min(
                    parent.width - 6 * root.s,
                    parent.height - 4 * root.s
                )

                height: width

                radius: 10 * root.s

                color: emojiCell.selected
                    ? Theme.frameBg
                    : Qt.rgba(
                        0.94,
                        0.88,
                        0.84,
                        0.018
                    )

                border.width:
                    emojiCell.selected ? 1 : 0

                border.color: Theme.frameBorder

                Behavior on color {
                    ColorAnimation {
                        duration: Motion.fast
                    }
                }

                Text {
                    anchors.centerIn: parent

                    text: root.filtered[emojiCell.index][0]

                    font.family: "Noto Color Emoji"

                    /*
                     * Scale the emoji with the new larger cell.
                     */
                    font.pixelSize:
                        Math.min(
                            parent.width * 0.55,
                            parent.height * 0.55
                        )

                    renderType: Text.NativeRendering
                }

                MouseArea {
                    anchors.fill: parent

                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onEntered: {
                        root.selectedIndex =
                            emojiCell.index;
                    }

                    onClicked: {
                        root.selectedIndex =
                            emojiCell.index;

                        root.copyEmoji(
                            root.filtered[
                                emojiCell.index
                            ][0]
                        );
                    }
                }
            }
        }
    }

    /*
     * Same scrolling helper used by Launcher.
     */
    WheelScroller {
        anchors.fill: emojiGrid
        s: root.s
        flick: emojiGrid
    }

    /*
     * Empty state.
     */
    Text {
        anchors.centerIn: emojiGrid

        visible: root.filtered.length === 0

        text: root.query.length
            ? "No matches"
            : "No emojis"

        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
    }
}
