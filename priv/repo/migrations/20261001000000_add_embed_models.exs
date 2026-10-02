defmodule Repo.Migrations.CreateEmbedModels do
  use Ecto.Migration

  def change do
    create table(:embed_owners) do
      add :name, :string
      add :settings, :map
      add :addresses, {:array, :map}, default: []

      add :first_version_id, references(:versions)
      add :current_version_id, references(:versions)

      timestamps()
    end

    create table(:embed_items) do
      add :name, :string
      add :addresses, {:array, :map}, default: []

      add :owner_id, references(:embed_owners), null: false

      add :first_version_id, references(:versions)
      add :current_version_id, references(:versions)

      timestamps()
    end

    create index(:embed_items, [:owner_id])
  end
end
