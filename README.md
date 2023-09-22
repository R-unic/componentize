# Componentize

Componentize is a component system for Roblox, optionally using CollectionService for tagging. Here's some example code of a lava brick. You can use functions beginning with `Event_` to hook into any event of the linked instance. In this case, `Lava` is linked to a `BasePart`. `Touched` is an event of `BasePart`. Events connected this way are automatically added to the janitor, accessible via `self._janitor`.

![example](https://cdn.discordapp.com/attachments/1154116157641588826/1154116157826142250/image.png)

# Docs

Check out the [Wiki](https://github.com/R-unic/componentize/wiki) for any API reference and examples.