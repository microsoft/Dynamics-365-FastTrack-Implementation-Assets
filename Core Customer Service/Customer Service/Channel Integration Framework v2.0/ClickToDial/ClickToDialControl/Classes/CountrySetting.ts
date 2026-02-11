export interface CountrySetting {
    country: string;
    countryCode: string;
    mask: string;
    codeExtension: string;
    default?: boolean;
}

export const CountrySettings: CountrySetting[] = [
    {
        country: "United States",
        countryCode: "US",
        mask: "(***) ***-****",
        codeExtension: "+1",
        default: true
    },
    {
        country: "Canada",
        countryCode: "CA",
        mask: "(***) ***-****",
        codeExtension: "+1"
    },
    {
        country: "Ukraine",
        countryCode: "UA",
        mask: "(**) ***-**-**",
        codeExtension: "+380"
    },
    {
        country: "United Kingdom",
        countryCode: "GB",
        mask: "***** *****",
        codeExtension: "+44"
    },
    {
        country: "Afghanistan",
        countryCode: "AF",
        mask: "*** *** ****",
        codeExtension: "+93"
    },
    {
        country: "Albania",
        countryCode: "AL",
        mask: "*** *** ****",
        codeExtension: "+355"
    },
    {
        country: "Algeria",
        countryCode: "DZ",
        mask: "**** ** **",
        codeExtension: "+213"
    },
    {
        country: "American Samoa",
        countryCode: "AS",
        mask: "(***) ***-****",
        codeExtension: "+1"
    },
    {
        country: "Andorra",
        countryCode: "AD",
        mask: "*** ***",
        codeExtension: "+376"
    },
    {
        country: "Angola",
        countryCode: "AO",
        mask: "*** *** ***",
        codeExtension: "+244"
    },
    {
        country: "Argentina",
        countryCode: "AR",
        mask: "**-****-****",
        codeExtension: "+54"
    },
    {
        country: "Armenia",
        countryCode: "AM",
        mask: "*** *****",
        codeExtension: "+374"
    },
    {
        country: "Aruba",
        countryCode: "AW",
        mask: "*** ****",
        codeExtension: "+297"
    },
    {
        country: "Australia",
        countryCode: "AU",
        mask: "* ** *** ***",
        codeExtension: "+61"
    },
    {
        country: "Austria",
        countryCode: "AT",
        mask: "**** ******",
        codeExtension: "+43"
    },
    {
        country: "Azerbaijan",
        countryCode: "AZ",
        mask: "*** *** ** **",
        codeExtension: "+994"
    },
    {
        country: "Bahamas",
        countryCode: "BS",
        mask: "(***) ***-****",
        codeExtension: "+1"
    },
    {
        country: "Bahrain",
        countryCode: "BH",
        mask: "**** ****",
        codeExtension: "+973"
    },
    {
        country: "Bangladesh",
        countryCode: "BD",
        mask: "*****-******",
        codeExtension: "+880"
    },
    {
        country: "Barbados",
        countryCode: "BB",
        mask: "(***) ***-****",
        codeExtension: "+1"
    },
    {
        country: "Belarus",
        countryCode: "BY",
        mask: "* *** ***-**-**",
        codeExtension: "+375"
    },
    {
        country: "Belgium",
        countryCode: "BE",
        mask: "**** ** ** **",
        codeExtension: "+32"
    },
    {
        country: "Belize",
        countryCode: "BZ",
        mask: "***-****",
        codeExtension: "+501"
    },
    {
        country: "Bermuda",
        countryCode: "BM",
        mask: "(***) ***-****",
        codeExtension: "+1"
    },
    {
        country: "Bhutan",
        countryCode: "BT",
        mask: "** ** ** **",
        codeExtension: "+975"
    },
    {
        country: "Bolivia",
        countryCode: "BO",
        mask: "********",
        codeExtension: "+591"
    },
    {
        country: "Bosnia and Herzegovina",
        countryCode: "BA",
        mask: "*** *** ***",
        codeExtension: "+387"
    },
    {
        country: "Botswana",
        countryCode: "BW",
        mask: "** *** ***",
        codeExtension: "+267"
    },
    {
        country: "Brazil",
        countryCode: "BR",
        mask: "(**) *****-****",
        codeExtension: "+55"
    },
    {
        country: "British Virgin Islands",
        countryCode: "VG",
        mask: "(***) ***-****",
        codeExtension: "+1"
    },
    {
        country: "Bulgaria",
        countryCode: "BG",
        mask: "*** *** ***",
        codeExtension: "+359"
    },
    {
        country: "Cambodia",
        countryCode: "KH",
        mask: "*** *** ***",
        codeExtension: "+855"
    },
    {
        country: "Cameroon",
        countryCode: "CM",
        mask: "* ** ** ** **",
        codeExtension: "+237"
    },
    {
        country: "Chile",
        countryCode: "CL",
        mask: "(*) **** ****",
        codeExtension: "+56"
    },
    {
        country: "China",
        countryCode: "CN",
        mask: "*** **** ****",
        codeExtension: "+86"
    },
    {
        country: "Colombia",
        countryCode: "CO",
        mask: "*** *******",
        codeExtension: "+57"
    },
    {
        country: "Congo (DRC)",
        countryCode: "CD",
        mask: "**** *** ***",
        codeExtension: "+243"
    },
    {
        country: "Congo (Republic)",
        countryCode: "CG",
        mask: "** *** ****",
        codeExtension: "+242"
    },
    {
        country: "Costa Rica",
        countryCode: "CR",
        mask: "**** ****",
        codeExtension: "+506"
    },
    {
        country: "Croatia",
        countryCode: "HR",
        mask: "*** *** ****",
        codeExtension: "+385"
    },
    {
        country: "Cyprus",
        countryCode: "CY",
        mask: "** ******",
        codeExtension: "+357"
    },
    {
        country: "Czech Republic",
        countryCode: "CZ",
        mask: "*** *** ***",
        codeExtension: "+420"
    },
    {
        country: "Denmark",
        countryCode: "DK",
        mask: "** ** ** **",
        codeExtension: "+45"
    },
    {
        country: "Dominican Republic",
        countryCode: "DO",
        mask: "(***) ***-****",
        codeExtension: "+1"
    },
    {
        country: "Ecuador",
        countryCode: "EC",
        mask: "*** *** ****",
        codeExtension: "+593"
    },
    {
        country: "Egypt",
        countryCode: "EG",
        mask: "**** *** ****",
        codeExtension: "+20"
    },
    {
        country: "El Salvador",
        countryCode: "SV",
        mask: "**** ****",
        codeExtension: "+503"
    },
    {
        country: "Equatorial Guinea",
        countryCode: "GQ",
        mask: "*** *** ***",
        codeExtension: "+240"
    },
    {
        country: "Estonia",
        countryCode: "EE",
        mask: "**** ****",
        codeExtension: "+372"
    },
    {
        country: "Falkland Islands",
        countryCode: "FK",
        mask: "*****",
        codeExtension: "+500"
    },
    {
        country: "Faroe Islands",
        countryCode: "FO",
        mask: "******",
        codeExtension: "+298"
    },
    {
        country: "Fiji",
        countryCode: "FJ",
        mask: "*** ****",
        codeExtension: "+679"
    },
    {
        country: "Finland",
        countryCode: "FI",
        mask: "*** *******",
        codeExtension: "+358"
    },
    {
        country: "France",
        countryCode: "FR",
        mask: "** ** ** ** **",
        codeExtension: "+33"
    },
    {
        country: "French Polynesia",
        countryCode: "PF",
        mask: "** ** ** **",
        codeExtension: "+689"
    },
    {
        country: "Gabon",
        countryCode: "GA",
        mask: "** ** ** **",
        codeExtension: "+241"
    },
    {
        country: "Georgia",
        countryCode: "GE",
        mask: "*** ** ** **",
        codeExtension: "+995"
    },
    {
        country: "Germany",
        countryCode: "DE",
        mask: "***** *******",
        codeExtension: "+49"
    },
    {
        country: "Ghana",
        countryCode: "GH",
        mask: "*** *** ****",
        codeExtension: "+233"
    },
    {
        country: "Gibraltar",
        countryCode: "GI",
        mask: "********",
        codeExtension: "+350"
    },
    {
        country: "Greece",
        countryCode: "GR",
        mask: "*** *** ****",
        codeExtension: "+30"
    },
    {
        country: "Greenland",
        countryCode: "GL",
        mask: "** ** **",
        codeExtension: "+299"
    },
    {
        country: "Grenada",
        countryCode: "GD",
        mask: "(***) ***-****",
        codeExtension: "+1"
    },
    {
        country: "Guadeloupe",
        countryCode: "GP",
        mask: "**** ** ** **",
        codeExtension: "+590"
    },
    {
        country: "Guatemala",
        countryCode: "GT",
        mask: "**** ****",
        codeExtension: "+502"
    },
    {
        country: "Guyana",
        countryCode: "GY",
        mask: "*** ****",
        codeExtension: "+592"
    },
    {
        country: "Haiti",
        countryCode: "HT",
        mask: "** ** ****",
        codeExtension: "+509"
    },
    {
        country: "Honduras",
        countryCode: "HN",
        mask: "****-****",
        codeExtension: "+504"
    },
    {
        country: "Hong Kong",
        countryCode: "HK",
        mask: "**** ****",
        codeExtension: "+852"
    },
    {
        country: "Hungary",
        countryCode: "HU",
        mask: "** ** *** ****",
        codeExtension: "+36"
    },
    {
        country: "Iceland",
        countryCode: "IS",
        mask: "*** ****",
        codeExtension: "+354"
    },
    {
        country: "India",
        countryCode: "IN",
        mask: "****** *****",
        codeExtension: "+91"
    },
    {
        country: "Indonesia",
        countryCode: "ID",
        mask: "****-***-***",
        codeExtension: "+62"
    },

    {
        country: "Iraq",
        countryCode: "IQ",
        mask: "**** *** ****",
        codeExtension: "+964"
    },
    {
        country: "Ireland",
        countryCode: "IE",
        mask: "*** *** ****",
        codeExtension: "+353"
    },
    {
        country: "Isle of Man",
        countryCode: "IM",
        mask: "***** ******",
        codeExtension: "+44"
    },
    {
        country: "Israel",
        countryCode: "IL",
        mask: "***-***-****",
        codeExtension: "+972"
    },
    {
        country: "Italy",
        countryCode: "IT",
        mask: "*** *** ****",
        codeExtension: "+39"
    },
    {
        country: "Ivory Coast",
        countryCode: "CI",
        mask: "** ** ** **",
        codeExtension: "+225"
    },
    {
        country: "Jamaica",
        countryCode: "JM",
        mask: "(***) ***-****",
        codeExtension: "+1"
    },
    {
        country: "Japan",
        countryCode: "JP",
        mask: "***-****-****",
        codeExtension: "+81"
    },
    {
        country: "Jordan",
        countryCode: "JO",
        mask: "** **** ****",
        codeExtension: "+962"
    },
    {
        country: "Kazakhstan",
        countryCode: "KZ",
        mask: "* (***) *** ****",
        codeExtension: "+7"
    },
    {
        country: "Kenya",
        countryCode: "KE",
        mask: "**** ******",
        codeExtension: "+254"
    },
    {
        country: "Kosovo",
        countryCode: "XK",
        mask: "*** *** ***",
        codeExtension: "+383"
    },
    {
        country: "Kuwait",
        countryCode: "KW",
        mask: "*** *****",
        codeExtension: "+965"
    },
    {
        country: "Kyrgyzstan",
        countryCode: "KG",
        mask: "**** *** ***",
        codeExtension: "+996"
    },
    {
        country: "Latvia",
        countryCode: "LV",
        mask: "** *** ***",
        codeExtension: "+371"
    },
    {
        country: "Lebanon",
        countryCode: "LB",
        mask: "** *** ***",
        codeExtension: "+961"
    },
    {
        country: "Libya",
        countryCode: "LY",
        mask: "***-*******",
        codeExtension: "+218"
    },
    {
        country: "Liechtenstein",
        countryCode: "LI",
        mask: "*** *** ***",
        codeExtension: "+423"
    },
    {
        country: "Lithuania",
        countryCode: "LT",
        mask: "(*-***) *****",
        codeExtension: "+370"
    },
    {
        country: "Luxembourg",
        countryCode: "LU",
        mask: "*** *** ***",
        codeExtension: "+352"
    },
    {
        country: "Macedonia",
        countryCode: "MK",
        mask: "*** *** ***",
        codeExtension: "+389"
    },
    {
        country: "Madagascar",
        countryCode: "MG",
        mask: "*** ** *** **",
        codeExtension: "+261"
    },
    {
        country: "Malaysia",
        countryCode: "MY",
        mask: "***-*** ****",
        codeExtension: "+60"
    },
    {
        country: "Maldives",
        countryCode: "MV",
        mask: "***-****",
        codeExtension: "+960"
    },
    {
        country: "Malta",
        countryCode: "MT",
        mask: "**** ****",
        codeExtension: "+356"
    },
    {
        country: "Martinique",
        countryCode: "MQ",
        mask: "**** ** ** **",
        codeExtension: "+596"
    },
    {
        country: "Mauritania",
        countryCode: "MR",
        mask: "** ** ** **",
        codeExtension: "+222"
    },
    {
        country: "Mauritius",
        countryCode: "MU",
        mask: "***** ****",
        codeExtension: "+230"
    },
    {
        country: "Mexico",
        countryCode: "MX",
        mask: "*** *** ****",
        codeExtension: "+52"
    },
    {
        country: "Moldova",
        countryCode: "MD",
        mask: "**** ** ***",
        codeExtension: "+373"
    },
    {
        country: "Monaco",
        countryCode: "MC",
        mask: "** ** ** ** **",
        codeExtension: "+377"
    },
    {
        country: "Montenegro",
        countryCode: "ME",
        mask: "*** *** ***",
        codeExtension: "+382"
    },
    {
        country: "Morocco",
        countryCode: "MA",
        mask: "****-******",
        codeExtension: "+212"
    },
    {
        country: "Mozambique",
        countryCode: "MZ",
        mask: "** *** *****",
        codeExtension: "+258"
    },
    {
        country: "Myanmar",
        countryCode: "MM",
        mask: "** *** *****",
        codeExtension: "+95"
    },
    {
        country: "Namibia",
        countryCode: "NA",
        mask: "*** *** ****",
        codeExtension: "+264"
    },
    {
        country: "Nepal",
        countryCode: "NP",
        mask: "***-*******",
        codeExtension: "+977"
    },
    {
        country: "Netherlands",
        countryCode: "NL",
        mask: "** ********",
        codeExtension: "+31"
    },
    {
        country: "Netherlands Antilles",
        countryCode: "BQ",
        mask: "*** ****",
        codeExtension: "+599"
    },
    {
        country: "New Caledonia",
        countryCode: "NC",
        mask: "**.**.**",
        codeExtension: "+687"
    },
    {
        country: "New Zealand",
        countryCode: "NZ",
        mask: "*** *** *****",
        codeExtension: "+64"
    },
    {
        country: "Nicaragua",
        countryCode: "NI",
        mask: "**** ****",
        codeExtension: "+505"
    },
    {
        country: "Nigeria",
        countryCode: "NG",
        mask: "**** *** ****",
        codeExtension: "+234"
    },
    {
        country: "Norway",
        countryCode: "NO",
        mask: "*** ** ***",
        codeExtension: "+47"
    },
    {
        country: "Oman",
        countryCode: "OM",
        mask: "**** ****",
        codeExtension: "+968"
    },
    {
        country: "Pakistan",
        countryCode: "PK",
        mask: "**** *******",
        codeExtension: "+92"
    },
    {
        country: "Panama",
        countryCode: "PA",
        mask: "****-****",
        codeExtension: "+507"
    },
    {
        country: "Papua New Guinea",
        countryCode: "PG",
        mask: "**** ****",
        codeExtension: "+675"
    },
    {
        country: "Paraguay",
        countryCode: "PY",
        mask: "**** ******",
        codeExtension: "+595"
    },
    {
        country: "Peru",
        countryCode: "PE",
        mask: "*** *** ***",
        codeExtension: "+51"
    },
    {
        country: "Philippines",
        countryCode: "PH",
        mask: "**** *** ****",
        codeExtension: "+63"
    },
    {
        country: "Pitcairn Islands",
        countryCode: "PN",
        mask: "*** *** *****",
        codeExtension: "+64"
    },
    {
        country: "Poland",
        countryCode: "PL",
        mask: "*** *** ***",
        codeExtension: "+48"
    },
    {
        country: "Portugal",
        countryCode: "PT",
        mask: "*** *** ***",
        codeExtension: "+351"
    },
    {
        country: "Puerto Rico",
        countryCode: "PR",
        mask: "(***) ***-****",
        codeExtension: "+1"
    },
    {
        country: "Qatar",
        countryCode: "QA",
        mask: "**** ****",
        codeExtension: "+974"
    },
    {
        country: "Réunion",
        countryCode: "RE",
        mask: "**** ** ** **",
        codeExtension: "+262"
    },
    {
        country: "Romania",
        countryCode: "RO",
        mask: "**** *** ***",
        codeExtension: "+40"
    },
    {
        country: "Russia",
        countryCode: "RU",
        mask: "* (***) ***-**-**",
        codeExtension: "+7"
    },
    {
        country: "Saint Lucia",
        countryCode: "LC",
        mask: "(***) ***-****",
        codeExtension: "+1"
    },
    {
        country: "Samoa",
        countryCode: "WS",
        mask: "** *****",
        codeExtension: "+685"
    },
    {
        country: "San Marino",
        countryCode: "SM",
        mask: "** ** ** **",
        codeExtension: "+378"
    },
    {
        country: "Saudi Arabia",
        countryCode: "SA",
        mask: "*** *** ****",
        codeExtension: "+966"
    },
    {
        country: "Senegal",
        countryCode: "SN",
        mask: "** *** ** **",
        codeExtension: "+221"
    },
    {
        country: "Serbia",
        countryCode: "RS",
        mask: "*** *******",
        codeExtension: "+381"
    },
    {
        country: "Seychelles",
        countryCode: "SC",
        mask: "* *** ***",
        codeExtension: "+248"
    },
    {
        country: "Sierra Leone",
        countryCode: "SL",
        mask: "(***) ******",
        codeExtension: "+232"
    },
    {
        country: "Singapore",
        countryCode: "SG",
        mask: "**** ****",
        codeExtension: "+65"
    },
    {
        country: "Slovakia",
        countryCode: "SK",
        mask: "**** *** ***",
        codeExtension: "+421"
    },
    {
        country: "Slovenia",
        countryCode: "SI",
        mask: "*** *** ***",
        codeExtension: "+386"
    },
    {
        country: "Solomon Islands",
        countryCode: "SB",
        mask: "** *****",
        codeExtension: "+677"
    },
    {
        country: "Somalia",
        countryCode: "SO",
        mask: "* *******",
        codeExtension: "+252"
    },
    {
        country: "South Africa",
        countryCode: "ZA",
        mask: "*** *** ****",
        codeExtension: "+27"
    },
    {
        country: "South Korea",
        countryCode: "KR",
        mask: "***-****-****",
        codeExtension: "+82"
    },
    {
        country: "Spain",
        countryCode: "ES",
        mask: "*** ** ** **",
        codeExtension: "+34"
    },
    {
        country: "Sri Lanka",
        countryCode: "LK",
        mask: "*** *** ****",
        codeExtension: "+94"
    },
    {
        country: "Suriname",
        countryCode: "SR",
        mask: "***-****",
        codeExtension: "+597"
    },
    {
        country: "Sweden",
        countryCode: "SE",
        mask: "***-*** ** **",
        codeExtension: "+46"
    },
    {
        country: "Switzerland",
        countryCode: "CH",
        mask: "*** *** ** **",
        codeExtension: "+41"
    },
    {
        country: "Taiwan",
        countryCode: "TW",
        mask: "**** *** ***",
        codeExtension: "+886"
    },
    {
        country: "Thailand",
        countryCode: "TH",
        mask: "*** *** ****",
        codeExtension: "+66"
    },
    {
        country: "Togo",
        countryCode: "TG",
        mask: "** ** ** **",
        codeExtension: "+228"
    },
    {
        country: "Tonga",
        countryCode: "TO",
        mask: "*** ****",
        codeExtension: "+676"
    },
    {
        country: "Trinidad and Tobago",
        countryCode: "TT",
        mask: "(***) ***-****",
        codeExtension: "+1"
    },
    {
        country: "Tunisia",
        countryCode: "TN",
        mask: "** *** ***",
        codeExtension: "+216"
    },
    {
        country: "Turkey",
        countryCode: "TR",
        mask: "**** *** ** **",
        codeExtension: "+90"
    },
    {
        country: "Turks and Caicos Islands",
        countryCode: "TC",
        mask: "(***) ***-****",
        codeExtension: "+1"
    },
    {
        country: "U.S. Virgin Islands",
        countryCode: "VI",
        mask: "(***) ***-****",
        codeExtension: "+1"
    },
    {
        country: "Uganda",
        countryCode: "UG",
        mask: "**** ******",
        codeExtension: "+256"
    },
    {
        country: "United Arab Emirates",
        countryCode: "AE",
        mask: "*** *** ****",
        codeExtension: "+971"
    },
    {
        country: "Uruguay",
        countryCode: "UY",
        mask: "*** *** ***",
        codeExtension: "+598"
    },
    {
        country: "Venezuela",
        countryCode: "VE",
        mask: "****-******",
        codeExtension: "+58"
    },
    {
        country: "Vietnam",
        countryCode: "VN",
        mask: "*** *** ** **",
        codeExtension: "+84"
    },
    {
        country: "Yemen",
        countryCode: "YE",
        mask: "**** *** ***",
        codeExtension: "+967"
    },
    {
        country: "Zambia",
        countryCode: "ZM",
        mask: "*** *******",
        codeExtension: "+260"
    },
    {
        country: "Zimbabwe",
        countryCode: "ZW",
        mask: "*** *** ****",
        codeExtension: "+263"
    }
];