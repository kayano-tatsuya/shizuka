import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * "API keys" settings page.
 *
 * Surfaces the keyring-backed credentials used by the online features
 * (booru providers, Wallhaven, wallpaper photo sources, weather) instead of
 * forcing users to remember launcher slash-commands. Values are stored in the
 * system keyring via SecretService (KeyringStorage) and never written to
 * config.json.
 */
ContentPage {
    id: page
    forceWidth: true
    bottomContentPadding: 15

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "image"
            shape: MaterialShape.Shape.Cookie9Sided
            title: Translation.tr("Booru")

            StyledText {
                Layout.fillWidth: true
                Layout.maximumWidth: 600
                text: Translation.tr("Some booru providers need an account to raise rate limits and unlock NSFW results. Safebooru works without any credentials. All keys are stored in your system keyring, not the config file.")
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            GroupedList {
                ApiKeyField {
                    keyPath: ["apiKeys", "danbooru", "user"]
                    buttonIcon: "person"
                    text: Translation.tr("Danbooru username")
                    placeholderText: Translation.tr("username")
                    description: Translation.tr("Your Danbooru login name.")
                    getLink: "https://danbooru.donmai.us/profile"
                }
                ApiKeyField {
                    keyPath: ["apiKeys", "danbooru", "key"]
                    buttonIcon: "key"
                    text: Translation.tr("Danbooru API key")
                    placeholderText: Translation.tr("API key")
                    description: Translation.tr("Just the key, or paste the whole “?login=…&api_key=…” string — it is parsed automatically.")
                    getLink: "https://danbooru.donmai.us/profile"
                }
            }

            GroupedList {
                ApiKeyField {
                    keyPath: ["apiKeys", "gelbooru", "user"]
                    buttonIcon: "person"
                    text: Translation.tr("Gelbooru user ID")
                    placeholderText: Translation.tr("user id")
                    description: Translation.tr("The numeric id (not the username). Filled automatically if you paste the whole string into the key field below.")
                    getLink: "https://gelbooru.com/index.php?page=account&s=options"
                }
                ApiKeyField {
                    keyPath: ["apiKeys", "gelbooru", "key"]
                    buttonIcon: "key"
                    text: Translation.tr("Gelbooru API key")
                    placeholderText: Translation.tr("API key")
                    description: Translation.tr("Gelbooru shows this as “&api_key=…&user_id=…”. Paste it whole — the key and user id are extracted for you.")
                    getLink: "https://gelbooru.com/index.php?page=account&s=options"
                }
            }
        }

        ContentSection {
            icon: "wallpaper"
            shape: MaterialShape.Shape.Pill
            title: Translation.tr("Wallpapers")

            StyledText {
                Layout.fillWidth: true
                Layout.maximumWidth: 600
                text: Translation.tr("Online wallpaper sources. A Wallhaven key enables NSFW filtering and higher rate limits.")
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            GroupedList {
                ApiKeyField {
                    keyPath: ["apiKeys", "wallhaven"]
                    buttonIcon: "wallpaper"
                    text: Translation.tr("Wallhaven API key")
                    placeholderText: Translation.tr("API key")
                    getLink: "https://wallhaven.cc/settings/account"
                }
                ApiKeyField {
                    keyPath: ["apiKeys", "unsplash"]
                    buttonIcon: "photo_library"
                    text: Translation.tr("Unsplash access key")
                    placeholderText: Translation.tr("access key")
                    getLink: "https://unsplash.com/oauth/applications"
                }
                ApiKeyField {
                    keyPath: ["apiKeys", "pexels"]
                    buttonIcon: "photo_library"
                    text: Translation.tr("Pexels API key")
                    placeholderText: Translation.tr("API key")
                    getLink: "https://www.pexels.com/api/"
                }
            }
        }

        ContentSection {
            icon: "cloud"
            shape: MaterialShape.Shape.Cookie4Sided
            title: Translation.tr("Weather")

            GroupedList {
                ApiKeyField {
                    keyPath: ["apiKeys", "openweather"]
                    buttonIcon: "thermostat"
                    text: Translation.tr("OpenWeatherMap API key")
                    placeholderText: Translation.tr("API key")
                    getLink: "https://home.openweathermap.org/api_keys"
                }
            }
        }

        ContentSection {
            icon: "auto_stories"
            shape: MaterialShape.Shape.Ghostish
            title: Translation.tr("Manga")

            StyledText {
                Layout.fillWidth: true
                Layout.maximumWidth: 600
                text: Translation.tr("The manga reader uses public MangaDex endpoints and needs no API key.")
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }

        ContentSection {
            icon: "neurology"
            shape: MaterialShape.Shape.PixelCircle
            title: Translation.tr("AI")

            StyledText {
                Layout.fillWidth: true
                Layout.maximumWidth: 600
                text: Translation.tr("Model API keys are managed from the Intelligence sidebar tab, or with the matching launcher command.")
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }
}
