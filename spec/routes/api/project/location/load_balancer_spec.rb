# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Clover, "load-balancer" do
  let(:user) { create_account }

  let(:project) { user.create_project_with_default_policy("project-1") }

  let(:lb) do
    ps = Prog::Vnet::SubnetNexus.assemble(project.id, name: "subnet-1", location: "hetzner-hel1")
    Prog::Vnet::LoadBalancerNexus.assemble(ps.id, name: "lb-1", src_port: 80, dst_port: 80).subject
  end

  describe "unauthenticated" do
    it "cannot perform authenticated operations" do
      [
        [:get, "/api/project/#{project.ubid}/load-balancer"],
        [:post, "/api/project/#{project.ubid}/load-balancer", {name: "lb-1"}],
        [:delete, "/api/project/#{project.ubid}/location/#{lb.private_subnet.display_location}/load-balancer/#{lb.name}"],
        [:get, "/api/project/#{project.ubid}/location/#{lb.private_subnet.display_location}/load-balancer/#{lb.name}"],
        [:post, "/api/project/#{project.ubid}/location/#{lb.private_subnet.display_location}/load-balancer/#{lb.name}/attach-vm", {vm_id: "vm-1"}],
        [:post, "/api/project/#{project.ubid}/location/#{lb.private_subnet.display_location}/load-balancer/#{lb.name}/detach-vm", {vm_id: "vm-1"}],
        [:get, "/api/project/#{project.ubid}/location/#{lb.private_subnet.display_location}/load-balancer/id/#{lb.ubid}"]
      ].each do |method, path, body|
        send(method, path, body)

        expect(last_response).to have_api_error(401, "Please login to continue")
      end
    end
  end

  describe "authenticated" do
    before do
      login_api(user.email)
      lb_project = Project.create_with_id(name: "default").tap { _1.associate_with_project(_1) }
      allow(Config).to receive(:load_balancer_service_project_id).and_return(lb_project.id)
    end

    describe "list" do
      it "empty" do
        get "/api/project/#{project.ubid}/location/eu-north-h1/load-balancer"

        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)["items"]).to eq([])
      end

      it "success single" do
        lb

        get "/api/project/#{project.ubid}/location/eu-north-h1/load-balancer"

        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)["items"].length).to eq(1)
      end

      it "success multiple" do
        lb
        Prog::Vnet::LoadBalancerNexus.assemble(lb.private_subnet.id, name: "lb-2", src_port: 80, dst_port: 80).subject

        get "/api/project/#{project.ubid}/location/eu-north-h1/load-balancer"

        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)["items"].length).to eq(2)
      end
    end

    describe "id" do
      it "success" do
        get "/api/project/#{project.ubid}/location/#{lb.private_subnet.display_location}/load-balancer/id/#{lb.ubid}"

        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)["name"]).to eq("lb-1")
      end

      it "not found" do
        get "/api/project/#{project.ubid}/location/#{lb.private_subnet.display_location}/load-balancer/id/invalid"

        expect(last_response).to have_api_error(404, "Sorry, we couldn’t find the resource you’re looking for.")
      end
    end

    describe "create" do
      it "success" do
        ps = Prog::Vnet::SubnetNexus.assemble(project.id, name: "subnet-1", location: "hetzner-hel1").subject
        post "/api/project/#{project.ubid}/load-balancer/lb1", {
          private_subnet_id: ps.ubid,
          src_port: "80", dst_port: "80",
          health_check_endpoint: "/up", algorithm: "round_robin"
        }.to_json

        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)["name"]).to eq("lb1")
      end

      it "missing required parameters" do
        post "/api/project/#{project.ubid}/load-balancer/lb1", {}.to_json

        expect(last_response).to have_api_error(400, "Validation failed for following fields: body")
      end

      it "invalid private_subnet_id" do
        post "/api/project/#{project.ubid}/load-balancer/lb1", {
          private_subnet_id: "invalid",
          src_port: "80", dst_port: "80",
          health_check_endpoint: "/up", algorithm: "round_robin"
        }.to_json

        expect(last_response).to have_api_error(404, "Sorry, we couldn’t find the resource you’re looking for.")
      end
    end

    describe "delete" do
      it "success" do
        delete "/api/project/#{project.ubid}/location/#{lb.private_subnet.display_location}/load-balancer/#{lb.name}"

        expect(last_response.status).to eq(204)
      end

      it "not found" do
        delete "/api/project/#{project.ubid}/location/#{lb.private_subnet.display_location}/load-balancer/invalid"

        expect(last_response.status).to eq(204)
      end
    end

    describe "get" do
      it "success" do
        get "/api/project/#{project.ubid}/location/#{lb.private_subnet.display_location}/load-balancer/#{lb.name}"

        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)["name"]).to eq("lb-1")
      end

      it "not found" do
        get "/api/project/#{project.ubid}/location/#{lb.private_subnet.display_location}/load-balancer/invalid"

        expect(last_response).to have_api_error(404, "Sorry, we couldn’t find the resource you’re looking for.")
      end
    end

    describe "attach-vm" do
      let(:vm) {
        nic = Nic.create_with_id(name: "nic-1", private_subnet_id: lb.private_subnet.id, mac: "00:00:00:00:00:01", private_ipv4: "1.1.1.1", private_ipv6: "2001:db8::1")
        vm = create_vm
        nic.update(vm_id: vm.id)
        vm
      }

      it "success" do
        vm.associate_with_project(project)
        post "/api/project/#{project.ubid}/location/#{lb.private_subnet.display_location}/load-balancer/#{lb.name}/attach-vm", {vm_id: vm.ubid}.to_json

        expect(last_response.status).to eq(200)
      end

      it "not found" do
        post "/api/project/#{project.ubid}/location/#{lb.private_subnet.display_location}/load-balancer/#{lb.name}/attach-vm", {vm_id: "invalid"}.to_json

        expect(last_response).to have_api_error(404, "Sorry, we couldn’t find the resource you’re looking for.")
      end
    end

    describe "detach-vm" do
      let(:vm) {
        nic = Nic.create_with_id(name: "nic-1", private_subnet_id: lb.private_subnet.id, mac: "00:00:00:00:00:01", private_ipv4: "1.1.1.1", private_ipv6: "2001:db8::1")
        vm = create_vm
        nic.update(vm_id: vm.id)
        vm
      }

      it "success" do
        vm.associate_with_project(project)
        lb.add_vm(vm)

        post "/api/project/#{project.ubid}/location/#{lb.private_subnet.display_location}/load-balancer/#{lb.name}/detach-vm", {vm_id: vm.ubid}.to_json

        expect(last_response.status).to eq(200)
      end

      it "not found" do
        post "/api/project/#{project.ubid}/location/#{lb.private_subnet.display_location}/load-balancer/#{lb.name}/detach-vm", {vm_id: "invalid"}.to_json

        expect(last_response).to have_api_error(404, "Sorry, we couldn’t find the resource you’re looking for.")
      end
    end
  end
end
