# ChinookReports

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Database Migrations

To create and migrate the database:

```bash
mix ecto.create        # create the database
mix ecto.migrate       # run all pending migrations
```

Or do both at once with:

```bash
mix ecto.setup         # create, migrate, and seed
```

To create a new migration:

```bash
mix ecto.gen.migration add_some_column_to_table
```

This generates a timestamped file in `priv/repo/migrations/`. Edit it to define your `up`/`change`, then run `mix ecto.migrate`.

To roll back the most recent migration:

```bash
mix ecto.rollback
```

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
