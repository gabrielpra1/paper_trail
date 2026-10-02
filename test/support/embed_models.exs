defmodule EmbedSettings do
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:theme, :string)
  end

  def changeset(settings, params), do: Ecto.Changeset.cast(settings, params, [:theme])
end

defmodule EmbedAddress do
  use Ecto.Schema

  embedded_schema do
    field(:street, :string)
  end

  def changeset(address, params), do: Ecto.Changeset.cast(address, params, [:street])
end

defmodule EmbedOwner do
  use Ecto.Schema

  import Ecto.Changeset

  schema "embed_owners" do
    field(:name, :string)
    embeds_one(:settings, EmbedSettings, on_replace: :update)
    embeds_many(:addresses, EmbedAddress, on_replace: :delete)

    has_many(:items, EmbedItem, foreign_key: :owner_id, on_replace: :delete)

    belongs_to(:first_version, PaperTrail.Version)
    belongs_to(:current_version, PaperTrail.Version, on_replace: :update)

    timestamps()
  end

  def changeset(owner, params \\ %{}) do
    owner
    |> cast(params, [:name])
    |> cast_embed(:settings, with: &EmbedSettings.changeset/2)
    |> cast_embed(:addresses, with: &EmbedAddress.changeset/2)
    |> cast_assoc(:items, with: &EmbedItem.changeset/2)
  end
end

defmodule EmbedItem do
  use Ecto.Schema

  import Ecto.Changeset

  schema "embed_items" do
    field(:name, :string)
    embeds_many(:addresses, EmbedAddress, on_replace: :delete)

    belongs_to(:owner, EmbedOwner, on_replace: :update)

    belongs_to(:first_version, PaperTrail.Version)
    belongs_to(:current_version, PaperTrail.Version, on_replace: :update)

    timestamps()
  end

  def changeset(item, params \\ %{}) do
    item
    |> cast(params, [:name])
    |> cast_embed(:addresses, with: &EmbedAddress.changeset/2)
  end

  def with_owner_changeset(item, params) do
    item
    |> changeset(params)
    |> cast_assoc(:owner, with: &EmbedOwner.changeset/2)
  end
end
