defmodule PaperTrailTest.Embeds do
  use ExUnit.Case

  import Ecto.Query

  alias PaperTrail.Version

  @repo PaperTrail.RepoClient.repo()

  setup do
    clean_up()
    on_exit(&clean_up/0)
    :ok
  end

  for function <- [:update, :update!, :multi_update], strict_mode <- [false, true] do
    describe "#{function} with strict_mode: #{strict_mode}" do
      setup do
        %{update: &do_update(unquote(function), &1, strict_mode: unquote(strict_mode))}
      end

      test "records the persisted embeds_one alongside regular field changes", %{update: update} do
        owner = insert_owner(settings: %EmbedSettings{theme: "light"})

        update.(EmbedOwner.changeset(owner, %{name: "renamed", settings: %{theme: "dark"}}))

        assert %{"name" => "renamed", "settings" => %{"theme" => "dark"}} =
                 latest_item_changes(owner)
      end

      test "records an embeds_one removal as nil", %{update: update} do
        owner = insert_owner(settings: %EmbedSettings{theme: "light"})

        update.(EmbedOwner.changeset(owner, %{settings: nil}))

        assert %{"settings" => nil} = latest_item_changes(owner)
      end

      test "records an added embeds_many entry with its generated id", %{update: update} do
        owner = insert_owner()

        %EmbedOwner{addresses: [%EmbedAddress{id: id}]} =
          update.(EmbedOwner.changeset(owner, %{addresses: [%{street: "Main St"}]}))

        assert is_binary(id)

        assert %{"addresses" => [%{"id" => ^id, "street" => "Main St"}]} =
                 latest_item_changes(owner)
      end

      test "records an edited embeds_many entry", %{update: update} do
        owner = insert_owner(addresses: [%EmbedAddress{street: "Old St"}])
        [%EmbedAddress{id: id}] = owner.addresses

        update.(EmbedOwner.changeset(owner, %{addresses: [%{id: id, street: "New St"}]}))

        assert %{"addresses" => [%{"id" => ^id, "street" => "New St"}]} =
                 latest_item_changes(owner)
      end

      test "records an embeds_many removal as an empty list", %{update: update} do
        owner = insert_owner(addresses: [%EmbedAddress{street: "Old St"}])

        update.(EmbedOwner.changeset(owner, %{addresses: []}))

        assert %{"addresses" => []} = latest_item_changes(owner)
      end

      test "records the persisted embeds of nested has_many changesets", %{update: update} do
        owner = insert_owner()
        kept = @repo.insert!(%EmbedItem{owner_id: owner.id, name: "kept"})
        @repo.insert!(%EmbedItem{owner_id: owner.id, name: "replaced"})
        owner = @repo.preload(owner, :items)

        params = %{
          items: [
            %{id: kept.id, addresses: [%{street: "Kept St"}]},
            %{name: "inserted", addresses: [%{street: "Inserted St"}]}
          ]
        }

        updated = update.(EmbedOwner.changeset(owner, params))

        [%EmbedAddress{id: kept_address_id}] =
          Enum.find(updated.items, &(&1.id == kept.id)).addresses

        [%EmbedAddress{id: inserted_address_id}] =
          Enum.find(updated.items, &(&1.name == "inserted")).addresses

        items = latest_item_changes(owner)["items"]

        assert %{
                 "changes" => %{
                   "addresses" => [%{"id" => ^kept_address_id, "street" => "Kept St"}]
                 }
               } =
                 Enum.find(items, &(&1["event"] == "update"))

        assert %{
                 "changes" => %{
                   "name" => "inserted",
                   "addresses" => [%{"id" => ^inserted_address_id, "street" => "Inserted St"}]
                 }
               } =
                 Enum.find(items, &(&1["event"] == "insert"))

        assert %{"data" => %{"name" => "replaced"}} =
                 Enum.find(items, &(&1["event"] == "replace"))
      end

      test "records the persisted embeds of a nested belongs_to changeset", %{update: update} do
        owner = insert_owner(settings: %EmbedSettings{theme: "light"})

        item =
          @repo.insert!(%EmbedItem{owner_id: owner.id, name: "item"}) |> @repo.preload(:owner)

        update.(
          EmbedItem.with_owner_changeset(item, %{
            owner: %{id: owner.id, settings: %{theme: "dark"}}
          })
        )

        assert %{
                 "owner" => %{
                   "event" => "update",
                   "changes" => %{"settings" => %{"theme" => "dark"}}
                 }
               } =
                 latest_item_changes(item)
      end
    end
  end

  test "update/2 returns the version with the persisted embeds" do
    owner = insert_owner()

    {:ok, %{model: model, version: version}} =
      PaperTrail.update(EmbedOwner.changeset(owner, %{addresses: [%{street: "Main St"}]}))

    [%EmbedAddress{id: id}] = model.addresses
    assert %{addresses: [%{id: ^id, street: "Main St"}]} = version.item_changes
  end

  defp do_update(:update, changeset, opts) do
    {:ok, %{model: model}} = PaperTrail.update(changeset, opts)
    model
  end

  defp do_update(:update!, changeset, opts), do: PaperTrail.update!(changeset, opts)

  defp do_update(:multi_update, changeset, opts) do
    {:ok, %{model: model}} =
      Ecto.Multi.new()
      |> PaperTrail.Multi.update(changeset, opts)
      |> PaperTrail.Multi.commit(opts)

    model
  end

  defp insert_owner(attrs \\ []), do: @repo.insert!(struct(%EmbedOwner{name: "owner"}, attrs))

  defp latest_item_changes(%schema{id: id}) do
    item_type = schema |> Module.split() |> List.last()

    from(v in Version,
      where: v.item_type == ^item_type and v.item_id == ^id,
      order_by: [desc: v.id],
      limit: 1
    )
    |> @repo.one!()
    |> Map.fetch!(:item_changes)
  end

  defp clean_up do
    @repo.delete_all(EmbedItem)
    @repo.delete_all(EmbedOwner)
    @repo.delete_all(Version)
  end
end
