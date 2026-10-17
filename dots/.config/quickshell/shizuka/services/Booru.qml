pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import Quickshell;
import QtQuick;

/**
 * A service for interacting with various booru APIs.
 */
Singleton {
    id: root
    property Component booruResponseDataComponent: BooruResponseData {}

    signal tagSuggestion(string query, var suggestions)
    signal responseFinished()

    property string failMessage: Translation.tr("That didn't work. Tips:\n- Check your tags and NSFW settings\n- If you don't have a tag in mind, type a page number")
    property var responses: []
    property int runningRequests: 0
    property var defaultUserAgent: Config.options?.networking?.userAgent || "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
    property var providerList: Object.keys(providers).filter(provider => provider !== "system" && providers[provider].api)
    property var providers: {
        "system": { "name": Translation.tr("System") },
        "yandere": {
            "name": "yande.re",
            "url": "https://yande.re",
            "api": "https://yande.re/post.json",
            "description": Translation.tr("All-rounder | Good quality, decent quantity"),
            "mapFunc": (response) => {
                return asArray(response).map(item => {
                    return {
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags,
                        "rating": item.rating,
                        "is_nsfw": (item.rating != 's'),
                        "md5": item.md5,
                        "preview_url": item.preview_url,
                        "sample_url": item.sample_url ?? item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_ext,
                        "source": getWorkingImageSource(item.source) ?? item.file_url,
                    }
                })
            },
            "tagSearchTemplate": "https://yande.re/tag.json?order=count&limit=10&name={{query}}*",
            "tagMapFunc": (response) => {
                return asArray(response).map(item => {
                    return {
                        "name": item.name,
                        "count": item.count
                    }
                })
            }
        },
        "konachan": {
            "name": "Konachan",
            "url": "https://konachan.net",
            "api": "https://konachan.net/post.json",
            "description": Translation.tr("For desktop wallpapers | Good quality"),
            "mapFunc": (response) => {
                return asArray(response).map(item => {
                    return {
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags,
                        "rating": item.rating,
                        "is_nsfw": (item.rating != 's'),
                        "md5": item.md5,
                        "preview_url": item.preview_url,
                        "sample_url": item.sample_url ?? item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_ext,
                        "source": getWorkingImageSource(item.source) ?? item.file_url,
                    }
                })
            },
            "tagSearchTemplate": "https://konachan.net/tag.json?order=count&limit=10&name={{query}}*",
            "tagMapFunc": (response) => {
                return asArray(response).map(item => {
                    return {
                        "name": item.name,
                        "count": item.count
                    }
                })
            }
        },
        "zerochan": {
            "name": "Zerochan",
            "url": "https://www.zerochan.net",
            "api": "https://www.zerochan.net/?json",
            "description": Translation.tr("Clean stuff | Excellent quality, no NSFW"),
            "mapFunc": (response) => {
                response = response.items
                return asArray(response).map(item => {
                    return {
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": (item.tags ?? []).join(" "),
                        "rating": "safe", // Zerochan doesn't have nsfw
                        "is_nsfw": false,
                        "md5": item.md5,
                        "preview_url": item.thumbnail,
                        "sample_url": item.thumbnail,
                        "file_url": item.thumbnail,
                        "file_ext": "avif",
                        "source": getWorkingImageSource(item.source) ?? item.thumbnail,
                        "character": item.tag
                    }
                })
            }
        },
        "danbooru": {
            "name": "Danbooru",
            "url": "https://danbooru.donmai.us",
            "api": "https://danbooru.donmai.us/posts.json",
            "description": Translation.tr("The popular one | Best quantity, but quality can vary wildly"),
            "mapFunc": (response) => {
                return asArray(response).map(item => {
                    return {
                        "id": item.id,
                        "width": item.image_width,
                        "height": item.image_height,
                        "aspect_ratio": item.image_width / item.image_height,
                        "tags": item.tag_string,
                        "rating": item.rating,
                        "is_nsfw": (item.rating != 's'),
                        "md5": item.md5,
                        "preview_url": item.preview_file_url,
                        "sample_url": item.file_url ?? item.large_file_url,
                        "file_url": item.large_file_url,
                        "file_ext": item.file_ext,
                        "source": getWorkingImageSource(item.source) ?? item.file_url,
                    }
                })
            },
            "tagSearchTemplate": "https://danbooru.donmai.us/tags.json?limit=10&search[name_matches]={{query}}*",
            "tagMapFunc": (response) => {
                return asArray(response).map(item => {
                    return {
                        "name": item.name,
                        "count": item.post_count
                    }
                })
            }
        },
        "gelbooru": {
            "name": "Gelbooru",
            "url": "https://gelbooru.com",
            "api": "https://gelbooru.com/index.php?page=dapi&s=post&q=index&json=1",
            // Its image CDN rejects hotlinks without this Referer (302 →
            // hotlink.php → HTML), and QML's Image cannot send request headers.
            "imageReferer": "https://gelbooru.com/",
            "description": Translation.tr("The hentai one | Great quantity, a lot of NSFW, quality varies wildly"),
            "mapFunc": (response) => {
                // Gelbooru wraps results in `post` and omits that key entirely
                // when a query has no matches, so it must not be assumed to be
                // an array.
                return asArray(response.post).map(item => {
                    const rating = String(item.rating ?? "").toLowerCase();
                    const ratingCode = (rating === "general" || rating === "sensitive") ? "s"
                        : (rating === "questionable" ? "q" : "e");
                    return {
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags,
                        "rating": ratingCode,
                        "is_nsfw": ratingCode !== "s",
                        "md5": item.md5,
                        "preview_url": item.preview_url,
                        "sample_url": item.sample_url ?? item.file_url,
                        "file_url": item.file_url,
                        // Gelbooru's JSON has no file_ext field
                        "file_ext": item.file_ext ?? String(item.file_url ?? "").split('.').pop(),
                        "source": getWorkingImageSource(item.source) ?? item.file_url,
                    }
                })
            },
            "tagSearchTemplate": "https://gelbooru.com/index.php?page=dapi&s=tag&q=index&json=1&orderby=count&limit=10&name_pattern={{query}}%",
            "tagMapFunc": (response) => {
                return asArray(response.tag).map(item => {
                    return {
                        "name": item.name,
                        "count": item.count
                    }
                })
            }
        },
        "safebooru": {
            "name": "Safebooru",
            "url": "https://safebooru.donmai.us",
            "api": "https://safebooru.donmai.us/posts.json",
            "description": Translation.tr("Safe only | Danbooru quality without the NSFW"),
            "mapFunc": (response) => {
                return asArray(response).map(item => {
                    return {
                        "id": item.id,
                        "width": item.image_width,
                        "height": item.image_height,
                        "aspect_ratio": item.image_width / item.image_height,
                        "tags": item.tag_string,
                        "rating": item.rating,
                        "is_nsfw": (item.rating != 's' && item.rating != 'g'),
                        "md5": item.md5,
                        "preview_url": item.preview_file_url,
                        "sample_url": item.file_url ?? item.large_file_url,
                        "file_url": item.large_file_url,
                        "file_ext": item.file_ext,
                        "source": getWorkingImageSource(item.source) ?? item.file_url,
                    }
                })
            },
            "tagSearchTemplate": "https://safebooru.donmai.us/tags.json?limit=10&search[name_matches]={{query}}*",
            "tagMapFunc": (response) => {
                return asArray(response).map(item => {
                    return {
                        "name": item.name,
                        "count": item.post_count
                    }
                })
            }
        },
        "waifu.im": {
            "name": "waifu.im",
            "url": "https://waifu.im",
            "api": "https://api.waifu.im/images",
            "description": Translation.tr("Waifus only | Excellent quality, limited quantity"),
            "mapFunc": (response) => {
                response = response.items
                return asArray(response).map(item => {
                    return {
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": (item.tags ?? []).map(tag => {return tag.name}).join(" "),
                        "rating": item.isNsfw ? "e" : "s",
                        "is_nsfw": item.isNsfw,
                        "md5": item.md5,
                        "preview_url": item.sample_url ?? item.url, // preview_url just says access denied (maybe i fucked up and sent too many requests idk)
                        "sample_url": item.url,
                        "file_url": item.url,
                        "file_ext": item.extension,
                        "source": getWorkingImageSource(item.source) ?? item.url,
                    }
                })
            },
            "tagSearchTemplate": "https://api.waifu.im/tags?Name={{query}}",
            "tagMapFunc": (response) => {
                return asArray(response.items).map(item => {return {"name": item.name}})
            }
        },
        "t.alcy.cc": {
            "name": "Alcy",
            "url": "https://t.alcy.cc",
            "api": "https://t.alcy.cc/",
            "description": Translation.tr("Large images | God tier quality, no NSFW."),
            "fixedTags": [
                {
                    "name": "ycy",
                    "count": "General"
                },
                {
                    "name": "moez",
                    "count": "Moe"
                },
                {
                    "name": "ysz",
                    "count": "Genshin Impact"
                },
                {
                    "name": "fj",
                    "count": "Landscape"
                },
                {
                    "name": "bd",
                    "count": "Girl on white background"
                },
                {
                    "name": "xhl",
                    "count": "Shiggy"
                },
            ],
            "manualParseFunc": (responseText) => {
                // Alcy just returns image links, each on a new line
                const lines = responseText.trim().split('\n').filter(line => line.length > 0);
                return lines.map(line => {
                    return {
                        "id": Qt.md5(line),
                        // Alcy doesn't provide dimensions and images are often of god resolution
                        "width": 1000,
                        "height": 1000,
                        "aspect_ratio": 1,
                        "tags": "[no tags]",
                        "rating": "s",
                        "is_nsfw": false,
                        "md5": Qt.md5(line),
                        "preview_url": line,
                        "sample_url": line,
                        "file_url": line,
                        "file_ext": line.split('.').pop(),
                        "source": "",
                    }
                });
            },
        }
    }
    property var currentProvider: Persistent.states.booru.provider

    /**
     * Coerce an API payload into an array. Providers sometimes omit the list
     * key entirely when a query has no results (e.g. Gelbooru returns only
     * `@attributes`), or return a single object instead of a list — either
     * would otherwise crash the mapper with ".map of undefined".
     */
    function asArray(value) {
        if (value === undefined || value === null) return [];
        if (Array.isArray(value)) return value;
        if (typeof value === "object") return [value];
        return [];
    }

    function getWorkingImageSource(url) {
        if (url?.includes('pximg.net')) {
            return `https://www.pixiv.net/en/artworks/${url.substring(url.lastIndexOf('/') + 1).replace(/_p\d+\.(png|jpg|jpeg|gif)$/, '')}`;
        }
        return url;
    }
    
    function setProvider(provider) {
        provider = provider.toLowerCase()
        if (providerList.indexOf(provider) !== -1) {
            Persistent.states.booru.provider = provider
            root.addSystemMessage(Translation.tr("Provider set to ") + providers[provider].name
                + (provider == "zerochan" ? Translation.tr(". Notes for Zerochan:\n- You must enter a color\n- Set your zerochan username in `sidebar.booru.zerochan.username` config option. You [might be banned for not doing so](https://www.zerochan.net/api#:~:text=The%20request%20may%20still%20be%20completed%20successfully%20without%20this%20custom%20header%2C%20but%20your%20project%20may%20be%20banned%20for%20being%20anonymous.)!") : ""))
        } else {
            root.addSystemMessage(Translation.tr("Invalid API provider. Supported: \n- ") + providerList.join("\n- "))
        }
    }

    function clearResponses() {
        responses = []
    }

    function addSystemMessage(message) {
        responses = [...responses, root.booruResponseDataComponent.createObject(null, {
            "provider": "system",
            "tags": [],
            "page": -1,
            "images": [],
            "message": `${message}`
        })]
    }

    function constructRequestUrl(tags, nsfw=true, limit=20, page=1, provider) {
        if (provider === undefined) provider = currentProvider;
        var baseUrl = providers[provider].api
        var url = baseUrl
        var tagString = tags.join(" ").trim()
        if (!nsfw && !(["zerochan", "waifu.im", "t.alcy.cc"].includes(provider))) {
            // Moebooru (yande.re/Konachan) uses rating:safe; Danbooru-family
            // (Danbooru/Safebooru) and Gelbooru use rating:general. Using the
            // wrong tag silently returns zero posts. Append without leaving a
            // leading space, which some providers reject.
            const ratingTag = ["yandere", "konachan"].includes(provider) ? "rating:safe" : "rating:general";
            tagString = tagString.length > 0 ? (tagString + " " + ratingTag) : ratingTag;
        }
        var params = []
        // Tags & limit
        if (provider === "zerochan") {
            params.push("c=" + tagString)
            params.push("l=" + limit)
            params.push("s=" + "fav")
            params.push("t=" + 1)
            params.push("p=" + page)
        }
        else if (provider === "waifu.im") {
            // waifu.im answers HTTP 400 when IncludedTags is present but empty,
            // so only send the tags that are actually set (none = any image).
            const tagsArray = tagString.length > 0
                ? tagString.split(" ").filter(tag => tag.length > 0)
                : [];
            tagsArray.forEach(tag => {
                params.push("IncludedTags=" + encodeURIComponent(tag.toLowerCase()));
            });
            params.push("PageSize=" + Math.min(limit, 30))
            params.push("IsNsfw=" + (nsfw ? "All" : "False"))
        }
        else if (provider === "t.alcy.cc") {
            url += tagString
            params.push("json")
            params.push("quantity=" + limit)
        }
        else {
            params.push("tags=" + encodeURIComponent(tagString))
            params.push("limit=" + limit)
            if (provider == "gelbooru") {
                params.push("pid=" + page)
            }
            else {
                params.push("page=" + page)
            }
        }
        params.push(...root.authParams(provider))
        if (baseUrl.indexOf("?") === -1) {
            url += "?" + params.join("&")
        } else {
            url += "&" + params.join("&")
        }
        return url
    }

    /**
     * Credentials from the keyring, keyed by provider (see ApiKeyField /
     * the "API keys" settings page). Only used by providers that support
     * authentication; empty when unset so anonymous requests still work.
     */
    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}

    /**
     * Pull a named value out of a credential string. Providers like Gelbooru
     * show the credentials as one query fragment, e.g.
     *   "&api_key=XXXX&user_id=1234"
     * so people paste the whole thing into a single field. Returns "" when the
     * parameter is not present (so a bare value can be used as-is instead).
     */
    function extractQueryParam(value, name) {
        if (value === undefined || value === null) return "";
        const s = String(value).trim();
        if (s.length === 0) return "";
        const match = s.match(new RegExp("[?&]?" + name + "=([^&\\s]+)"));
        return match ? decodeURIComponent(match[1]) : "";
    }

    function authParams(provider) {
        if (provider === undefined) provider = currentProvider;
        const out = []
        if (provider === "danbooru") {
            const rawUser = String(root.apiKeys?.danbooru?.user ?? "").trim()
            const rawKey = String(root.apiKeys?.danbooru?.key ?? "").trim()
            const user = root.extractQueryParam(rawUser, "login") || rawUser
            const key = root.extractQueryParam(rawKey, "api_key") || rawKey
            if (user && key) {
                out.push("login=" + encodeURIComponent(user))
                out.push("api_key=" + encodeURIComponent(key))
            }
        } else if (provider === "gelbooru") {
            const rawUser = String(root.apiKeys?.gelbooru?.user ?? "").trim()
            const rawKey = String(root.apiKeys?.gelbooru?.key ?? "").trim()
            // Accept either the bare key or a pasted "?api_key=...&user_id=..."
            // fragment. Gelbooru wants the *numeric* user id, which is often only
            // available inside that fragment, so prefer it when present.
            const key = root.extractQueryParam(rawKey, "api_key") || rawKey
            const user = root.extractQueryParam(rawKey, "user_id")
                || root.extractQueryParam(rawUser, "user_id")
                || rawUser
            if (user && key) {
                out.push("api_key=" + encodeURIComponent(key))
                out.push("user_id=" + encodeURIComponent(user))
            }
        }
        return out
    }

    function makeRequest(tags, nsfw=false, limit=20, page=1, provider) {
        if (provider === undefined) provider = currentProvider;
        var url = constructRequestUrl(tags, nsfw, limit, page, provider)
        console.log("[Booru] Making request to " + url)

        const newResponse = root.booruResponseDataComponent.createObject(null, {
            "provider": provider,
            "tags": tags,
            "page": page,
            "images": [],
            "message": ""
        })

        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    // console.log("[Booru] Raw response: " + xhr.responseText)
                    const p = provider
                    let response;
                    if (providers[p].manualParseFunc) {
                        response = providers[p].manualParseFunc(xhr.responseText)
                    } else {
                        response = JSON.parse(xhr.responseText)
                        response = providers[p].mapFunc(response)
                    }
                    // console.log("[Booru] Mapped response: " + JSON.stringify(response))
                    // Some hosts (Gelbooru) hotlink-protect their image CDN and
                    // only serve a file when the request carries a matching
                    // Referer. Keep it on each image so bookmarks stay valid
                    // across provider switches.
                    const referer = providers[p].imageReferer ?? ""
                    if (referer)
                        for (const img of response) img.imageReferer = referer

                    newResponse.images = response
                    newResponse.message = response.length > 0 ? "" : root.failMessage
                    
                } catch (e) {
                    console.log("[Booru] Failed to parse response: " + e)
                    newResponse.message = root.failMessage
                } finally {
                    root.runningRequests--;
                    root.responses = [...root.responses, newResponse]
                }
            }
            else if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("[Booru] Request failed with status: " + xhr.status)
                newResponse.message = root.failMessage
                root.runningRequests--;
                root.responses = [...root.responses, newResponse]
            }
            root.responseFinished()
        }

        try {
            // Required for danbooru and konachan
            if (["danbooru", "safebooru", "konachan"].includes(provider)) {
                xhr.setRequestHeader("User-Agent", defaultUserAgent)
            }
            else if (provider == "zerochan") {
                const userAgent = Config.options?.sidebar?.booru?.zerochan?.username ? `Desktop sidebar booru viewer - username: ${Config.options.sidebar.booru.zerochan.username}` : defaultUserAgent
                xhr.setRequestHeader("User-Agent", userAgent)
            }
            root.runningRequests++;
            xhr.send()
        } catch (error) {
            console.log("Could not set User-Agent:", error)
        } 
    }

    property var currentTagRequest: null
    function triggerTagSearch(query) {
        if (currentTagRequest) {
            currentTagRequest.abort();
        }

        var provider = providers[currentProvider]
        if (provider.fixedTags) {
            root.tagSuggestion(query, provider.fixedTags)
            return provider.fixedTags;
        } else if (!provider.tagSearchTemplate) {
            return
        }
        var url = provider.tagSearchTemplate.replace("{{query}}", encodeURIComponent(query))

        var xhr = new XMLHttpRequest()
        currentTagRequest = xhr
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                currentTagRequest = null
                try {
                    // console.log("[Booru] Raw response: " + xhr.responseText)
                    var response = JSON.parse(xhr.responseText)
                    response = provider.tagMapFunc(response)
                    // console.log("[Booru] Mapped response: " + JSON.stringify(response))
                    root.tagSuggestion(query, response)
                } catch (e) {
                    console.log("[Booru] Failed to parse response: " + e)
                }
            }
            else if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("[Booru] Request failed with status: " + xhr.status)
            }
        }

        try {
            // Required for danbooru and konachan
            if (["danbooru", "safebooru", "konachan"].includes(currentProvider)) {
                xhr.setRequestHeader("User-Agent", defaultUserAgent)
            }
            xhr.send()
        } catch (error) {
            console.log("Could not set User-Agent:", error)
        } 
    }
}
