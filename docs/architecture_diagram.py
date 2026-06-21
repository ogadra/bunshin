"""Generate the Bunshin AWS architecture diagram."""

from pathlib import Path

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import ECS
from diagrams.aws.database import Dynamodb
from diagrams.aws.network import CloudFront, ELB, Endpoint, GlobalAccelerator, Route53
from diagrams.aws.security import WAF
from diagrams.aws.storage import S3
from diagrams.onprem.client import Users

CLUSTER_FONT = {"fontsize": "20", "fontname": "Sans-Serif Bold"}

GRAPH_ATTR = {
    "fontsize": "32",
    "bgcolor": "white",
    "pad": "0.8",
    "nodesep": "0.9",
    "ranksep": "1.7",
    "compound": "true",
    **CLUSTER_FONT,
}

NODE_ATTR = {
    "fontsize": "16",
    "fontname": "Sans-Serif Bold",
    "labelloc": "b",
    "imagepos": "tc",
}

EDGE_ATTR = {
    "fontsize": "16",
    "fontname": "Sans-Serif Bold",
}

OUTPUT_FILE = str(Path(__file__).with_name("bunshin_architecture"))


def region_stack(name: str, cidr: str, azs: str) -> dict[str, object]:
    with Cluster(name, graph_attr={**CLUSTER_FONT, "margin": "20"}):
        static = S3("S3 Static Assets")
        ddb = Dynamodb("DynamoDB\nbunshin-runners")

        with Cluster(f"VPC {cidr}", graph_attr={**CLUSTER_FONT, "margin": "16"}):
            with Cluster(f"Private Subnets ({azs})", graph_attr={**CLUSTER_FONT, "margin": "20"}):
                api_alb = ELB("API Ingress ALB\ninternal HTTPS")
                internal_alb = ELB("Internal ALB\nregional HTTPS")
                private_dns = Route53(f"Private DNS\n{name}.domain")

                with Cluster("ECS Cluster: bunshin", graph_attr={**CLUSTER_FONT, "margin": "24"}):
                    nginx = ECS("NGINX\n1 task / ARM64")
                    runner = ECS("Runner\nFargate / x86_64")
                    broker = ECS("Broker\n1 task / ARM64")

                vpce_gateway = Endpoint("Gateway VPCE\nDynamoDB")
                vpce_interface = Endpoint("Interface VPCE\nECR / Logs")

                api_alb >> nginx
                internal_alb >> nginx
                private_dns >> internal_alb
                nginx >> Edge(label="proxy") >> runner
                nginx >> Edge(label="auth_request") >> broker
                runner >> Edge(label="register") >> broker
                vpce_gateway >> Edge(style="invis") >> vpce_interface
                vpce_interface >> Edge(style="invis") >> api_alb
                api_alb >> Edge(style="invis") >> internal_alb
                internal_alb >> Edge(style="invis") >> nginx

        broker >> ddb

    return {
        "api_alb": api_alb,
        "internal_alb": internal_alb,
        "nginx": nginx,
        "broker": broker,
        "runner": runner,
        "static": static,
        "private_dns": private_dns,
    }


def main() -> None:
    with Diagram(
        "Bunshin - AWS Architecture",
        show=False,
        filename=OUTPUT_FILE,
        outformat="png",
        direction="LR",
        graph_attr=GRAPH_ATTR,
        node_attr=NODE_ATTR,
        edge_attr=EDGE_ATTR,
    ):
        users = Users("Clients")
        public_dns = Route53("Route 53\nPublic DNS")
        waf = WAF("AWS WAF\nCloudFront ACL")
        cloudfront = CloudFront("CloudFront")
        accelerator = GlobalAccelerator("Global Accelerator\napi-ingress")

        users >> public_dns >> cloudfront
        waf >> cloudfront
        cloudfront >> Edge(xlabel="PATH: /api/*") >> accelerator

        apne1 = region_stack("ap-northeast-1", "10.0.0.0/16", "1a / 1c / 1d")
        apne3 = region_stack("ap-northeast-3", "10.1.0.0/16", "3a / 3b / 3c")

        cloudfront >> Edge(label="PATH: / primary") >> apne1["static"]
        cloudfront >> Edge(label="PATH: / failover") >> apne3["static"]
        apne1["static"] >> Edge(label="S3 replication", constraint="false") >> apne3["static"]

        accelerator >> Edge(label="weight 128") >> apne1["api_alb"]
        accelerator >> Edge(label="weight 128") >> apne3["api_alb"]

        apne1["nginx"] >> Edge(label="cross-region HTTPS", style="dashed", constraint="false") >> apne3["internal_alb"]
        apne3["nginx"] >> Edge(label="cross-region HTTPS", style="dashed", constraint="false") >> apne1["internal_alb"]
        apne1["private_dns"] >> Edge(label="VPC peering DNS", style="dashed", constraint="false") >> apne3["private_dns"]


if __name__ == "__main__":
    main()
