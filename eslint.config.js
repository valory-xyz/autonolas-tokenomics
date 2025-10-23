const {
    defineConfig,
    globalIgnores,
} = require("eslint/config");

const globals = require("globals");

module.exports = defineConfig([{
    languageOptions: {
        globals: {
            ...globals.browser,
            ...globals.commonjs,
        },

        "ecmaVersion": 13,
        parserOptions: {},
    },

    "rules": {
        "camelcase": [2, {
            "properties": "always",
        }],

        "indent": ["error", 4],
        "linebreak-style": ["error", "unix"],
        "quotes": ["error", "double"],
        "semi": ["error", "always"],
        "no-unused-vars": "warn",
    },
}, globalIgnores(["artifacts/*", "cache/*", "node_modules/*", "third_party/*"]), globalIgnores(["**/coverage*", "audits/*", "lib/*"])]);
